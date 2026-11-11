#!/usr/bin/env python3
"""sentinel_1_load_demo.ipynb's STAC loads (see odc_demo.py) with stacgrid.py.
  python sg_demo.py <stacgrid dir> out.npz"""
import datetime as dt
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, sys.argv[1])
import stacgrid as sg  # noqa: E402

os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR")
SAMPLE = "/vsicurl/https://deant-data-public-dev.s3.ap-southeast-2.amazonaws.com/fast-ice/s1a_EW_20191217_hh_gamma0_db_sample.tif"
PARQUET = "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
t0 = time.time()
grid = sg.grid_from_raster(SAMPLE)
where = sg.grid_footprint(grid)
obs = dt.datetime(2019, 12, 17, 11, 25, 53)
span = lambda d: f"{(obs - d).isoformat()}/{(obs + d).isoformat()}"  # noqa: E731
api_items = sg.stac_search("https://explorer.dev.dea.ga.gov.au/stac", ["ga_s1_nrb_iw_hh_1"],
                           datetime=span(dt.timedelta(days=6)), intersects=where)
api_groups = sg.group_items(api_items, "sat:relative_orbit")
api = sg.stac_load(api_groups, ["hh_gamma0"], grid)["hh_gamma0"]
pq_items = sg.items_from_geoparquet(PARQUET, ["ga_s1_nrb_ew_hh_hv_1"], datetime=span(dt.timedelta(hours=1)), intersects=where)
pq_groups = sg.group_items(pq_items, "sat:relative_orbit")
pq = sg.stac_load(pq_groups, ["hh_gamma0"], grid)["hh_gamma0"]
xl, yb, xr, yt = grid["extent"]
np.savez_compressed(sys.argv[2], gt=np.array([xl, grid["res"], 0.0, yt, 0.0, -grid["res"]]),
                    shape=np.array([grid["height"], grid["width"]]),
                    api=api, api_time=np.array(list(api_groups)), api_ids=np.array([i["id"] for i in api_items]),
                    pq=pq, pq_time=np.array(list(pq_groups)), pq_ids=np.array([i["id"] for i in pq_items]))
print(json.dumps(dict(api_items=len(api_items), api_groups=list(api_groups), api_shape=api.shape,
                      pq_items=len(pq_items), pq_shape=pq.shape, s=round(time.time() - t0, 1))))
