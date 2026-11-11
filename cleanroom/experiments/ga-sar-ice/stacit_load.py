#!/usr/bin/env python3
"""The odc_load.py load again, this time with GDAL's STACIT driver doing the STAC search and mosaic.

STACIT opens a STAC search URL as one virtual mosaic of its items (it follows the "next"
links itself). There's no time axis, so each solar day is its own search: the day's UTC window
is shifted by the AOI centre's longitude/15 hours. Each day's mosaic is warped (nearest) onto
the grid, as before.

  python3 stacit_load.py out.npz
"""
import datetime as dt
import json
import math
import os
import sys
import time
import urllib.parse

import numpy as np
from osgeo import gdal, osr

gdal.UseExceptions()
os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2",
                  GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="5")
STAC = "https://explorer.dev.dea.ga.gov.au/stac/search"
L, B, R, T = 73.5, -69.1, 74.0, -68.8
RES, CRS = 200, "EPSG:3031"
START, END = dt.date(2021, 1, 1), dt.date(2021, 3, 1)
BANDS = ["hh_gamma0", "oa_layover_shadow_mask"]
OO = [o for o in os.environ.get("STACIT_OO", "").split(",") if o]  # extra open options to try


def srs(d):
    s = osr.SpatialReference(); s.SetFromUserInput(d)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


def main():
    print("GDAL", gdal.__version__, "STACIT open options:")
    print(gdal.GetDriverByName("STACIT").GetMetadataItem("DMD_OPENOPTIONLIST"))
    t0 = time.time()
    ct = osr.CoordinateTransformation(srs("EPSG:4326"), srs(CRS))
    xl, yb, xr, yt = ct.TransformBounds(L, B, R, T, 21)
    xl, yb = math.floor(xl / RES) * RES, math.floor(yb / RES) * RES
    xr, yt = math.ceil(xr / RES) * RES, math.ceil(yt / RES) * RES
    w, h = int(round((xr - xl) / RES)), int(round((yt - yb) / RES))
    shift = dt.timedelta(hours=(L + R) / 2 / 15)
    days, out, n_open_fail = [], {b: [] for b in BANDS}, 0
    # solar days whose UTC window overlaps the search period (pystac-client's END is inclusive)
    d = START - dt.timedelta(days=1)
    while d <= END + dt.timedelta(days=1):
        t_a = dt.datetime.combine(d, dt.time()) - shift
        t_b = t_a + dt.timedelta(days=1)
        t_a = max(t_a, dt.datetime.combine(START, dt.time()))
        t_b = min(t_b, dt.datetime.combine(END, dt.time(23, 59, 59)))
        d += dt.timedelta(days=1)
        if t_b <= t_a:
            continue
        q = urllib.parse.urlencode(dict(collections="ga_s1_nrb_iw_hh_1", bbox=f"{L},{B},{R},{T}", limit=100,
                                        datetime=f"{t_a:%Y-%m-%dT%H:%M:%SZ}/{t_b:%Y-%m-%dT%H:%M:%SZ}"), safe=",:/")
        layers = []
        for b in BANDS:
            try:
                src = gdal.OpenEx(f'STACIT:"{STAC}?{q}"', gdal.OF_RASTER, open_options=[f"ASSET={b}", *OO])
            except RuntimeError as e:
                # an empty day and a day whose items GDAL can't place both end up here
                n_open_fail += 1
                print(d - dt.timedelta(days=1), b, "no usable asset:", e)
                break
            wd = gdal.Warp("", src, format="MEM", dstSRS=CRS, outputBounds=(xl, yb, xr, yt),
                           width=w, height=h, resampleAlg="near")
            layers.append(wd.GetRasterBand(1).ReadAsArray())
        if len(layers) == len(BANDS):
            days.append((d - dt.timedelta(days=1)).isoformat())
            for b, a in zip(BANDS, layers):
                out[b].append(a)
    t1 = time.time()
    if not days:
        sys.exit(f"no days loaded ({n_open_fail} open failures)")
    np.savez_compressed(sys.argv[1], hh=np.stack(out["hh_gamma0"]), mask=np.stack(out["oa_layover_shadow_mask"]),
                        time=np.array(days), gt=np.array([xl, RES, 0.0, yt, 0.0, -RES]), shape=np.array([h, w]),
                        item_ids=np.array([]))
    print(json.dumps(dict(shape=[len(days), h, w], days=days, days_without_usable_asset=n_open_fail, load_s=round(t1 - t0, 1))))


if __name__ == "__main__":
    main()
