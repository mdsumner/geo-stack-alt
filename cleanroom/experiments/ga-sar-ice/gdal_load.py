#!/usr/bin/env python3
"""The same load as odc_load.py with osgeo.gdal and the standard library only.

STAC search is one POST (paged) to /search; the grid is the AOI in EPSG:3031 snapped outwards
to 200 m; each solar day is the items of that day warped (nearest) onto the grid in time order,
first valid pixel wins (odc-stac's default fuser).

  python3 gdal_load.py out.npz
"""
import datetime as dt
import json
import math
import os
import sys
import time
import urllib.request

import numpy as np
from osgeo import gdal, osr

gdal.UseExceptions()
os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2",
                  GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", GDAL_HTTP_MAX_RETRY="5")
STAC = "https://explorer.dev.dea.ga.gov.au/stac/search"
L, B, R, T = 73.5, -69.1, 74.0, -68.8
RES, CRS = 200, "EPSG:3031"
BANDS = ["hh_gamma0", "oa_layover_shadow_mask"]
FUSE = os.environ.get("GDAL_LOAD_FUSE", "first")  # first valid wins (odc-stac), or "last" (a VRT mosaic)
OVR = os.environ.get("GDAL_LOAD_OVR", "AUTO")  # AUTO (gdalwarp's default) or NONE: full-resolution reads


def srs(d):
    s = osr.SpatialReference(); s.SetFromUserInput(d)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return s


def search() -> list[dict]:
    body = dict(collections=["ga_s1_nrb_iw_hh_1"], limit=100,
                datetime="2021-01-01T00:00:00Z/2021-03-01T23:59:59Z",  # pystac-client's expansion
                intersects=dict(type="Polygon", coordinates=[[[L, B], [R, B], [R, T], [L, T], [L, B]]]))
    feats, req = [], urllib.request.Request(STAC, json.dumps(body).encode(), {"Content-Type": "application/json"})
    while req is not None:
        page = json.load(urllib.request.urlopen(req, timeout=120))
        feats += page["features"]
        nxt = [k for k in page.get("links", []) if k.get("rel") == "next"]
        req = None
        if nxt:
            n = nxt[0]
            data = json.dumps({**body, **n.get("body", {})}).encode() if n.get("method", "GET") == "POST" else None
            req = urllib.request.Request(n["href"], data, {"Content-Type": "application/json"})
    return feats


def href(item, band):
    h = item["assets"][band]["href"]
    return "/vsis3/" + h[5:] if h.startswith("s3://") else "/vsicurl/" + h


def solar_day(item) -> str:
    t = dt.datetime.fromisoformat(item["properties"]["datetime"].replace("Z", "+00:00"))
    lon = (item["bbox"][0] + item["bbox"][2]) / 2
    return (t + dt.timedelta(hours=lon / 15)).date().isoformat()


def main():
    t0 = time.time()
    items = search()
    print(f"Found {len(items)} items")
    t1 = time.time()
    # grid: AOI polygon in EPSG:3031 (densified), bounds snapped outwards to the resolution
    ct = osr.CoordinateTransformation(srs("EPSG:4326"), srs(CRS))
    xl, yb, xr, yt = ct.TransformBounds(L, B, R, T, 21)
    xl, yb = math.floor(xl / RES) * RES, math.floor(yb / RES) * RES
    xr, yt = math.ceil(xr / RES) * RES, math.ceil(yt / RES) * RES
    w, h = int(round((xr - xl) / RES)), int(round((yt - yb) / RES))
    groups = {}
    for it in sorted(items, key=lambda i: i["properties"]["datetime"]):
        groups.setdefault(solar_day(it), []).append(it)
    days = sorted(groups)
    out = {b: [] for b in BANDS}
    for d in days:
        for b in BANDS:
            acc = None
            for it in groups[d]:
                wd = gdal.Warp("", href(it, b), format="MEM", dstSRS=CRS, outputBounds=(xl, yb, xr, yt),
                               width=w, height=h, resampleAlg="near", overviewLevel=OVR)
                band = wd.GetRasterBand(1)
                a, nd = band.ReadAsArray(), band.GetNoDataValue()
                valid = np.isfinite(a) if nd is None or math.isnan(nd) else a != nd
                if acc is None:
                    acc, accv, fill = a.copy(), valid.copy(), (np.nan if nd is None else nd)
                    acc[~valid] = fill
                else:
                    take = valid & ~accv if FUSE == "first" else valid
                    acc[take] = a[take]
                    accv |= take
            out[b].append(acc)
    t2 = time.time()
    np.savez_compressed(sys.argv[1], hh=np.stack(out["hh_gamma0"]), mask=np.stack(out["oa_layover_shadow_mask"]),
                        time=np.array(days), gt=np.array([xl, RES, 0.0, yt, 0.0, -RES]), shape=np.array([h, w]),
                        item_ids=np.array(sorted(i["id"] for i in items)))
    print(json.dumps(dict(n_items=len(items), shape=[len(days), h, w], gt=[xl, RES, 0.0, yt, 0.0, -RES],
                          search_s=round(t1 - t0, 1), load_s=round(t2 - t1, 1))))


if __name__ == "__main__":
    main()
