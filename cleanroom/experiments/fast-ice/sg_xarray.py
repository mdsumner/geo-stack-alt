#!/usr/bin/env python3
"""fast_ice_from_stac_xarray.ipynb's two loads (see odc_xarray.py) with stacgrid.py.
  python sg_xarray.py <stacgrid dir> out.npz"""
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, sys.argv[1])
import stacgrid as sg  # noqa: E402

os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR")
BBOX = (165.5, -77.85, 168.0, -77.45)
grid = sg.grid_from_bbox(BBOX, "EPSG:3031", 40)
xl, yb, xr, yt = grid["extent"]
t0 = time.time()
# EW: the notebook filters the GeoParquet with datetime >= "2019-01-01" and <= "2020-01-01" (midnight)
ew_items = sg.items_from_geoparquet(
    "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet",
    ["ga_s1_nrb_ew_hh_hv_1"], datetime="2019-01-01T00:00:00Z/2020-01-01T00:00:00Z", bbox=BBOX)
ew_groups = sg.group_items(ew_items, "time")
ew = sg.stac_load(ew_groups, ["hh_gamma0"], grid)["hh_gamma0"]
t_ew = time.time() - t0
t1 = time.time()
# IW: the notebook searches with intersects=AOI_BBOX.boundary(), the bbox outline as a LineString
ring = [[BBOX[0], BBOX[1]], [BBOX[2], BBOX[1]], [BBOX[2], BBOX[3]], [BBOX[0], BBOX[3]], [BBOX[0], BBOX[1]]]
iw_items = sg.stac_search("https://explorer.dev.dea.ga.gov.au/stac", ["ga_s1_nrb_iw_hh_1"],
                          datetime="2019-01-01/2020-01-01", intersects=dict(type="LineString", coordinates=ring))
iw_groups = sg.group_items(iw_items, "solar_day", grid=grid)
iw = sg.stac_load(iw_groups, ["hh_gamma0"], grid)["hh_gamma0"]
t_iw = time.time() - t1
gt = np.array([xl, 40, 0.0, yt, 0.0, -40])
np.savez_compressed(sys.argv[2], ew=ew, ew_time=np.array(list(ew_groups)), ew_gt=gt, ew_ids=np.array([i["id"] for i in ew_items]),
                    iw=iw, iw_time=np.array(list(iw_groups)), iw_gt=gt, iw_ids=np.array(sorted(i["id"] for i in iw_items)))
print(json.dumps(dict(ew_items=len(ew_items), ew_shape=ew.shape, ew_s=round(t_ew, 1),
                      iw_items=len(iw_items), iw_shape=iw.shape, iw_s=round(t_iw, 1))))
