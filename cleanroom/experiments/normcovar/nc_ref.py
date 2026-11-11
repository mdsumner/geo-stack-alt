#!/usr/bin/env python3
"""fast-ice notebooks/fast_ice_from_stac_xarray.ipynb sections 3, 5-10 (EW load, dB, pairs, NormCovar,
RGB, resample, landmask) as a script: the reference for the ports.

Cells copied from abradley60/fast-ice 4694c6c, with normalized_covariance (jlo031) d6843d2 called as
the notebook calls it. Changes: the GeoParquet is fetched with urllib (same URL, same bytes); the
coastline is fetched with urllib from fast_ice.datasets.coastline's URL and checked against its
pooch hash; outputs are saved instead of plotted. SAM/SVM (sections 12-15) are not run.
  python nc_ref.py out.npz"""
import hashlib
import json
import os
import sys
import tempfile
import time
import urllib.request
import zipfile

import geopandas as gpd
import numpy as np
import pandas as pd
import shapely
import stac_geoparquet
from normalized_covariance import normcovar
from odc.geo import BoundingBox
from odc.stac import configure_s3_access, load

os.environ["AWS_DEFAULT_REGION"] = "ap-southeast-2"
configure_s3_access(cloud_defaults=True, aws_unsigned=True)


def to_item_collection(gdf):
    """stac_geoparquet.to_item_collection after casting datetime columns to ns (pandas 3; see
    ../fast-ice/odc_xarray.py)."""
    gdf = gdf.copy()
    for k in gdf.select_dtypes(include=["datetimetz", "datetime"]).columns:
        gdf[k] = gdf[k].astype("datetime64[ns, UTC]")
    return stac_geoparquet.to_item_collection(gdf)


# ---- 2. Parameters ----
AOI_BBOX = BoundingBox(left=165.5, bottom=-77.85, right=168.0, top=-77.45, crs="EPSG:4326")
START_TIME, END_TIME = "2019-01-01", "2020-01-01"
OUTPUT_CRS, RESOLUTION = "EPSG:3031", 40
WINDOWS = [11, 21, 33]
MIN_TEMP_BASELINE, MAX_TEMP_BASELINE = 11.9, 12.1
NP_MIN, NP_MAX = -0.5, 1.0
EW_PARQUET_URL = "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
EW_COLLECTION, EW_BAND = "ga_s1_nrb_ew_hh_hv_1", "hh_gamma0"
COAST_URL = ("https://ramadda.data.bas.ac.uk/repository/entry/get/"
             "add_coastline_medium_res_polygon_v7_12.shp.zip?entryid=synth%3Ac9c6d671-ad19-4a78-96b2-7d47e9bac46a"
             "%3AL2FkZF9jb2FzdGxpbmVfbWVkaXVtX3Jlc19wb2x5Z29uX3Y3XzEyLnNocC56aXA%3D")
COAST_SHA256 = "b0172d698436f871f49339cea5c7155e3d98648360521cc4bbc44a026c0edc38"
tmp = tempfile.mkdtemp()
times_s = {}

# ---- 3. EW from STAC GeoParquet ----
t0 = time.time()
pq = os.path.join(tmp, "ew.parquet")
urllib.request.urlretrieve(EW_PARQUET_URL, pq)
gdf_ew = gpd.read_parquet(pq)
aoi_shape = shapely.geometry.shape(AOI_BBOX.polygon)
filtered_ew = gdf_ew[(gdf_ew["collection"] == EW_COLLECTION) & (gdf_ew.intersects(aoi_shape)) &
                     (gdf_ew["datetime"] >= START_TIME) & (gdf_ew["datetime"] <= END_TIME)
                     ].copy().sort_values("datetime").reset_index(drop=True)
stac_items_ew = to_item_collection(filtered_ew)
ds_ew = load(stac_items_ew, bands=[EW_BAND], chunks={}, resolution=RESOLUTION, crs=OUTPUT_CRS, geopolygon=aoi_shape)

# ---- 5. dB (CONVERT_TO_DB = True, no speckle filter) ----
ew_db = 10 * np.log10(ds_ew[EW_BAND].where(ds_ew[EW_BAND] > 0))
ds_ew_db = ds_ew.assign({"hh_gamma0_db": ew_db}).drop_vars(EW_BAND)
ds_proc, band_proc = ds_ew_db, "hh_gamma0_db"   # PROCESS_MODE = "ew"

# ---- 6. pairs ----
times = pd.DatetimeIndex(ds_proc.time.values)
valid_pairs = []
for i in range(len(times)):
    for j in range(i + 1, len(times)):
        delta_days = abs((times[j] - times[i]).total_seconds()) / 86400
        if MIN_TEMP_BASELINE <= delta_days <= MAX_TEMP_BASELINE:
            valid_pairs.append((i, j, delta_days))

# ---- 7. first pair ----
idx1, idx2, baseline = valid_pairs[0]
img1 = ds_proc[band_proc].isel(time=idx1).drop_vars("time").compute()
img2 = ds_proc[band_proc].isel(time=idx2).drop_vars("time").compute()
times_s["load_pair"] = round(time.time() - t0, 1)

# ---- 8. coastline + NormCovar ----
z = os.path.join(tmp, "coast.zip")
urllib.request.urlretrieve(COAST_URL, z)
assert hashlib.sha256(open(z, "rb").read()).hexdigest() == COAST_SHA256
zipfile.ZipFile(z).extractall(os.path.join(tmp, "coast"))
landmask_shapefile_path = os.path.join(tmp, "coast", "add_coastline_medium_res_polygon_v7_12.shp")
t1 = time.time()
results = normcovar.fully_process_image_pair_xr(
    img1, img2, windows=WINDOWS, NP_min=NP_MIN, NP_max=NP_MAX, resample_rgb=True,
    resample_method="bilinear", zoom_x=10, zoom_y=10, landmask_shapefile_path=landmask_shapefile_path,
    erode_landmask=None, apply_landmask_to_rgb=True)
times_s["normcovar"] = round(time.time() - t1, 1)


def gt(da):
    a = da.odc.geobox.affine
    return np.array([a.c, a.a, a.b, a.f, a.d, a.e])


band_last = lambda da: np.moveaxis(da.values, -1, 0) if da.ndim == 3 else da.values  # noqa: E731
out = dict(img1=img1.values, img2=img2.values, gt=gt(img1), gt_resampled=gt(results["rgb_resampled"]),
           pair=np.array([str(times[idx1]), str(times[idx2])]), n_pairs=len(valid_pairs),
           times=np.array([str(t) for t in times]),
           **{f"normcovar_{w}": results["normcovar"][w].values for w in WINDOWS},
           **{k: band_last(results[k]) for k in ("rgb", "rgb_resampled", "landmask", "landmask_resampled",
                                                 "rgb_landmasked", "rgb_resampled_landmasked")})
np.savez_compressed(sys.argv[1], **out)
print(json.dumps(dict(items=len(stac_items_ew), groups=len(times), pairs=len(valid_pairs), pair=out["pair"].tolist(),
                      baseline_days=baseline, shape=list(img1.shape), resampled=list(results["rgb_resampled"].shape),
                      rgb_attrs={k: str(v) for k, v in results["rgb"].attrs.items()},
                      img1_attrs={k: str(v) for k, v in img1.attrs.items()},
                      landmask_frac=float(results["landmask"].values.mean()), s=times_s)))
