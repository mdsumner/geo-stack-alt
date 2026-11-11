#!/usr/bin/env python3
"""fast-ice notebooks/fast_ice_from_stac_xarray.ipynb, sections 2-4 (the loads), as a script.

Cells copied from abradley60/fast-ice 4694c6c; changes: the GeoParquet is fetched with urllib
instead of fsspec (same URL, same bytes), the lazy loads are computed, and the results are saved.
  python odc_xarray.py out.npz
"""
import json
import os
import sys
import tempfile
import time
import urllib.request

import geopandas as gpd
import numpy as np
import shapely
import stac_geoparquet
from odc.geo import BoundingBox
from odc.stac import configure_s3_access, load
from pystac_client import Client

os.environ["AWS_DEFAULT_REGION"] = "ap-southeast-2"
configure_s3_access(cloud_defaults=True, aws_unsigned=True)


def to_item_collection(gdf):
    """stac_geoparquet.to_item_collection, after casting datetime columns to ns. stac-geoparquet 0.8
    stringifies only datetime64[ns] columns; pandas 3 reads this file as datetime64[us, UTC], and
    pystac then fails on the raw Timestamps (TypeError: object of type 'Timestamp' has no len())."""
    gdf = gdf.copy()
    for k in gdf.select_dtypes(include=["datetimetz", "datetime"]).columns:
        gdf[k] = gdf[k].astype("datetime64[ns, UTC]")
    return stac_geoparquet.to_item_collection(gdf)

# ---- 2. Parameters (Erebus Ice Tongue) ----
AOI_BBOX = BoundingBox(left=165.5, bottom=-77.85, right=168.0, top=-77.45, crs="EPSG:4326")
START_TIME = "2019-01-01"
END_TIME = "2020-01-01"
OUTPUT_CRS = "EPSG:3031"
RESOLUTION = 40
EW_PARQUET_URL = "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
EW_COLLECTION = "ga_s1_nrb_ew_hh_hv_1"
EW_BAND = "hh_gamma0"
IW_STAC_ENDPOINT = "https://explorer.dev.dea.ga.gov.au/stac"
IW_COLLECTION = "ga_s1_nrb_iw_hh_1"
IW_BAND = "hh_gamma0"

t0 = time.time()
# ---- 3. EW from STAC GeoParquet ----
pq = os.path.join(tempfile.mkdtemp(), "ew.parquet")
urllib.request.urlretrieve(EW_PARQUET_URL, pq)
gdf_ew = gpd.read_parquet(pq)
aoi_shape = shapely.geometry.shape(AOI_BBOX.polygon)
filtered_ew = gdf_ew[
    (gdf_ew["collection"] == EW_COLLECTION) &
    (gdf_ew.intersects(aoi_shape)) &
    (gdf_ew["datetime"] >= START_TIME) &
    (gdf_ew["datetime"] <= END_TIME)
].copy().sort_values("datetime").reset_index(drop=True)
stac_items_ew = to_item_collection(filtered_ew)
ds_ew = load(stac_items_ew, bands=[EW_BAND], chunks={}, resolution=RESOLUTION, crs=OUTPUT_CRS,
             geopolygon=aoi_shape).compute()
t_ew = time.time() - t0

# ---- 4. IW from the STAC API ----
t1 = time.time()
stac_client = Client.open(IW_STAC_ENDPOINT)
iw_search = stac_client.search(collections=[IW_COLLECTION], datetime=f"{START_TIME}/{END_TIME}",
                               intersects=AOI_BBOX.boundary())
stac_items_iw = iw_search.item_collection()
ds_iw = load(stac_items_iw, bands=[IW_BAND], chunks={}, resolution=RESOLUTION, crs=OUTPUT_CRS,
             geopolygon=aoi_shape, groupby="solar_day").compute()
t_iw = time.time() - t1

def gt(ds):
    a = ds.odc.geobox.affine
    return np.array([a.c, a.a, a.b, a.f, a.d, a.e])

np.savez_compressed(sys.argv[1],
                    ew=ds_ew[EW_BAND].values, ew_time=ds_ew.time.values.astype(str), ew_gt=gt(ds_ew),
                    ew_ids=np.array([i.id for i in stac_items_ew]),
                    iw=ds_iw[IW_BAND].values, iw_time=ds_iw.time.values.astype(str), iw_gt=gt(ds_iw),
                    iw_ids=np.array(sorted(i.id for i in stac_items_iw)))
print(json.dumps(dict(ew_items=len(stac_items_ew), ew_shape=ds_ew[EW_BAND].shape, ew_s=round(t_ew, 1),
                      iw_items=len(stac_items_iw), iw_shape=ds_iw[IW_BAND].shape, iw_s=round(t_iw, 1),
                      ew_dtype=str(ds_ew[EW_BAND].dtype), ew_nodata=str(ds_ew[EW_BAND].attrs.get("nodata")),
                      iw_dtype=str(ds_iw[IW_BAND].dtype), iw_nodata=str(ds_iw[IW_BAND].attrs.get("nodata")))))
