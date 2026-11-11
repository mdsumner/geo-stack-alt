#!/usr/bin/env python3
"""fast-ice notebooks/sentinel_1_load_demo.ipynb (the STAC loads), as a script.

The notebook's calls go through fast_ice.io; its query and load functions are inlined here as
they are in abradley60/fast-ice 4694c6c (_stac_items_from_api, _stac_items_from_geoparquet,
load_sentinel_1_from_stac's odc.stac.load call), without the dB conversion or xarray metadata.
The sample EW GeoTIFF and the GeoParquet are fetched from the URLs in fast_ice.datasets.
  python odc_demo.py out.npz
"""
import json
import os
import sys
import tempfile
import time
import urllib.request
from datetime import datetime, timedelta

import geopandas as gpd
import numpy as np
import odc.geo.xr  # noqa: F401
import rioxarray
import stac_geoparquet
from odc.geo.xr import assign_crs
from odc.stac import configure_s3_access, load
from pystac_client import Client
from shapely.geometry import shape

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
tmp = tempfile.mkdtemp()
SAMPLE = "https://deant-data-public-dev.s3.ap-southeast-2.amazonaws.com/fast-ice/s1a_EW_20191217_hh_gamma0_db_sample.tif"
# fast_ice.datasets fetches this from data.dev.dea.ga.gov.au (HTTP 504 on 2026-11-11); the S3 copy
# the xarray notebook uses has the same sha256 as fast_ice's pooch registry (62eab128...)
PARQUET = "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
sample, pq = os.path.join(tmp, "sample.tif"), os.path.join(tmp, "ew.parquet")
urllib.request.urlretrieve(SAMPLE, sample)
urllib.request.urlretrieve(PARQUET, pq)

t0 = time.time()
# load_sentinel_1_from_file -> geobox, time, search geometry
da = rioxarray.open_rasterio(sample).squeeze("band", drop=True)
da = assign_crs(da, crs=da.rio.crs)
obs_geobox = da.odc.geobox
obs_time = datetime(2019, 12, 17, 11, 25, 53)
obs_search_geometry = obs_geobox.extent.to_crs("EPSG:4326")

# API, IW, +-6 days (fast_ice.io._stac_items_from_api)
items_api = Client.open("https://explorer.dev.dea.ga.gov.au/stac").search(
    collections=["ga_s1_nrb_iw_hh_1"],
    datetime=f"{(obs_time - timedelta(days=6)).isoformat()}/{(obs_time + timedelta(days=6)).isoformat()}",
    intersects=obs_search_geometry).item_collection()
obs_api = load(items_api, bands="hh_gamma0", groupby="sat:relative_orbit", chunks={}, geobox=obs_geobox).compute()

# GeoParquet, EW, +-1 hour (fast_ice.io._stac_items_from_geoparquet)
start_time, end_time = obs_time - timedelta(hours=1), obs_time + timedelta(hours=1)
stac_index = gpd.read_parquet(pq)
items_gdf = stac_index[stac_index["collection"] == "ga_s1_nrb_ew_hh_hv_1"]
items_gdf = items_gdf[(items_gdf.datetime >= start_time.isoformat()) & (items_gdf.datetime <= end_time.isoformat())]
items_gdf = items_gdf[items_gdf.intersects(shape(obs_search_geometry))]
items_pq = to_item_collection(items_gdf.copy().sort_values("datetime").reset_index(drop=True))
obs_pq = load(items_pq, bands="hh_gamma0", groupby="sat:relative_orbit", chunks={}, geobox=obs_geobox).compute()

a = obs_geobox.affine
np.savez_compressed(sys.argv[1], gt=np.array([a.c, a.a, a.b, a.f, a.d, a.e]), shape=np.array(obs_geobox.shape),
                    search_geometry=json.dumps(obs_search_geometry.json),
                    api=obs_api["hh_gamma0"].values, api_time=obs_api.time.values.astype(str),
                    api_ids=np.array([i.id for i in items_api]),
                    api_orbits=np.array([i.properties["sat:relative_orbit"] for i in items_api]),
                    pq=obs_pq["hh_gamma0"].values, pq_time=obs_pq.time.values.astype(str),
                    pq_ids=np.array([i.id for i in items_pq]))
print(json.dumps(dict(geobox=str(obs_geobox), api_items=len(items_api), api_shape=obs_api["hh_gamma0"].shape,
                      api_time=list(obs_api.time.values.astype(str)), pq_items=len(items_pq),
                      pq_shape=obs_pq["hh_gamma0"].shape, s=round(time.time() - t0, 1))))
