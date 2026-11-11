#!/usr/bin/env python3
"""nc_ref.py with the alt stack: stacgrid.py for the EW load, osgeo.gdal for the resample and the
landmask, numpy + scipy for the arithmetic. No odc, xarray, rasterio, rioxarray or geopandas.

The NormCovar arithmetic is normalized_covariance d6843d2's, line for line (scipy uniform_filter,
mode="nearest", float32). The geo steps, as the package does them through odc-geo / rasterio:
  resample   odc.geo xr_reproject onto geobox.zoom_to(round(shape / 10)): rasterio's warp with
             XSCALE=1 YSCALE=1 (odc-geo always sets them: bilinear from the 2x2 neighbours, not
             GDAL's default of averaging over the 10x10 footprint when downsampling)
  landmask   geopandas + rasterio.features.rasterize (all_touched=False): gdal.Rasterize
The reference's uint8 resamples go to rasterio with destination nodata 0 (odc-geo passes its fill
value as dst_nodata even for dst_nodata=None). From rasterio 1.5.1 that reaches GDAL's warper, which
then writes valid 0s as 1s ("changed to 1 ... to avoid being treated as NoData"): the resampled
landmask is all 1, and so the landmasked SAM input all 0. rasterio 1.5.0 (fast-ice's lock) didn't
pass it on. The port warps without nodata (= the locked reference); NC_ODC_NODATA=1 sets
dstNodata=0, to reproduce the reference on rasterio >= 1.5.1.
Only the two images of the first pair are loaded (the reference loads lazily, computes those two).
  python nc_gdal.py <stacgrid dir> <coastline .shp> out.npz"""
import json
import os
import sys
import time
from datetime import datetime

import numpy as np
from osgeo import gdal
from scipy.ndimage import uniform_filter

sys.path.insert(0, sys.argv[1])
import stacgrid as sg  # noqa: E402

gdal.UseExceptions()
os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR")
BBOX = (165.5, -77.85, 168.0, -77.45)
WINDOWS, NP_MIN, NP_MAX, ZOOM = [11, 21, 33], -0.5, 1.0, 10
MIN_TEMP_BASELINE, MAX_TEMP_BASELINE = 11.9, 12.1
DST_NODATA = 0 if os.environ.get("NC_ODC_NODATA") == "1" else None


# ---- normalized_covariance's array functions ----
def fill_nans(a):
    nan = np.isnan(a)
    return a if not nan.any() else np.where(nan, np.nanmean(a), a)


def dev_from_local_mean(a, w):
    f = fill_nans(a)
    return f - uniform_filter(f, size=w, mode="nearest")


def local_var(a, w):
    f = fill_nans(a)
    m, m2 = uniform_filter(f, size=w, mode="nearest"), uniform_filter(f**2, size=w, mode="nearest")
    return np.clip(m2 - m**2, a_min=0.0, a_max=None)


def normcovar(a1, a2, w):
    mv = fill_nans((local_var(a1, w) + local_var(a2, w)) * 0.5)
    covar = uniform_filter(dev_from_local_mean(a1, w) * dev_from_local_mean(a2, w), size=w, mode="nearest")
    return covar / uniform_filter(mv, size=w, mode="nearest")


def to_u8(a):
    return ((np.clip(a, NP_MIN, NP_MAX) - NP_MIN) / (NP_MAX - NP_MIN) * (255 - 0)).astype(np.uint8)


# ---- the geo steps, osgeo.gdal ----
def mem(arr, grid):
    """(band, y, x) array on `grid` as a MEM dataset."""
    nb, h, w = arr.shape
    ds = gdal.GetDriverByName("MEM").Create("", w, h, nb, gdal.GDT_Byte)
    ds.SetGeoTransform((grid["extent"][0], grid["res"], 0, grid["extent"][3], 0, -grid["res"]))
    ds.SetProjection(sg._srs(grid["crs"]).ExportToWkt())
    for b in range(nb):
        ds.GetRasterBand(b + 1).WriteArray(arr[b])
    return ds


def zoom(arr, grid, method):
    """odc's xr_reproject onto geobox.zoom_to(shape / ZOOM): same extent, round(shape / ZOOM) pixels."""
    h, w = arr.shape[-2:]
    nh, nw = max(1, round(h / ZOOM)), max(1, round(w / ZOOM))
    out = gdal.Warp("", mem(arr, grid), format="MEM", outputBounds=grid["extent"], width=nw, height=nh,
                    resampleAlg=method, warpOptions=["XSCALE=1", "YSCALE=1"], dstNodata=DST_NODATA)
    gt = out.GetGeoTransform()
    return out.ReadAsArray().reshape(arr.shape[0], nh, nw), np.array(gt)


def landmask(shp, grid):
    ds = gdal.GetDriverByName("MEM").Create("", grid["width"], grid["height"], 1, gdal.GDT_Byte)
    ds.SetGeoTransform((grid["extent"][0], grid["res"], 0, grid["extent"][3], 0, -grid["res"]))
    ds.SetProjection(sg._srs(grid["crs"]).ExportToWkt())
    gdal.Rasterize(ds, gdal.OpenEx(shp, gdal.OF_VECTOR), burnValues=[1])  # MEM bands start at 0
    return ds.ReadAsArray()


t0 = time.time()
grid = sg.grid_from_bbox(BBOX, "EPSG:3031", 40)
items = sg.items_from_geoparquet(
    "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet",
    ["ga_s1_nrb_ew_hh_hv_1"], datetime="2019-01-01T00:00:00Z/2020-01-01T00:00:00Z", bbox=BBOX)
groups = sg.group_items(items, "time")
when = [datetime.fromisoformat(k.replace("Z", "+00:00")) for k in groups]
pairs = [(i, j, abs((when[j] - when[i]).total_seconds()) / 86400) for i in range(len(when)) for j in range(i + 1, len(when))]
pairs = [p for p in pairs if MIN_TEMP_BASELINE <= p[2] <= MAX_TEMP_BASELINE]
i1, i2, baseline = pairs[0]
keys = list(groups)
hh = sg.stac_load({k: groups[k] for k in (keys[i1], keys[i2])}, ["hh_gamma0"], grid)["hh_gamma0"]
with np.errstate(divide="ignore", invalid="ignore"):
    db = 10 * np.log10(np.where(hh > 0, hh, np.float32(np.nan)))
img1, img2 = db[0], db[1]
t_load = time.time() - t0
t1 = time.time()
nc = {w: normcovar(img1, img2, w).astype(np.float32) for w in WINDOWS}
rgb = np.stack([to_u8(nc[w]) for w in WINDOWS])                      # (band, y, x)
rgb_res, gt_res = zoom(rgb, grid, "bilinear")
lm = landmask(sys.argv[2], grid)
lm_res, _ = zoom(lm[None], grid, "near")
rgb_lm = np.where(lm[None] != 1, rgb, 0).astype(np.uint8)
rgb_res_lm = np.where(lm_res != 1, rgb_res, 0).astype(np.uint8)
t_nc = time.time() - t1
xl, yb, xr, yt = grid["extent"]
np.savez_compressed(sys.argv[3], img1=img1, img2=img2, gt=np.array([xl, 40, 0.0, yt, 0.0, -40]), gt_resampled=gt_res,
                    pair=np.array([keys[i1], keys[i2]]), n_pairs=len(pairs), times=np.array(keys),
                    **{f"normcovar_{w}": nc[w] for w in WINDOWS}, rgb=rgb, rgb_resampled=rgb_res, landmask=lm,
                    landmask_resampled=lm_res[0], rgb_landmasked=rgb_lm, rgb_resampled_landmasked=rgb_res_lm)
print(json.dumps(dict(items=len(items), groups=len(groups), pairs=len(pairs), pair=[keys[i1], keys[i2]],
                      baseline_days=baseline, shape=list(img1.shape), resampled=list(rgb_res.shape),
                      landmask_frac=float(lm.mean()), s=dict(load_pair=round(t_load, 1), normcovar=round(t_nc, 1)))))
