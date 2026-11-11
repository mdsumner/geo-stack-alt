#!/usr/bin/env python3
"""The GA tutorial load (see ../ga-sar-ice/odc_load.py) with stacgrid.py.
  python3 ga_py.py <stacgrid dir> out.npz [overviews fuse]"""
import os
import sys
import time

import numpy as np

sys.path.insert(0, sys.argv[1])
import stacgrid as sg  # noqa: E402

os.environ.update(AWS_NO_SIGN_REQUEST="YES", AWS_REGION="ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR")
ovr, fuse = (sys.argv[3], sys.argv[4]) if len(sys.argv) > 4 else ("AUTO", "first")
BBOX = (73.5, -69.1, 74.0, -68.8)
t0 = time.time()
items = sg.stac_search("https://explorer.dev.dea.ga.gov.au/stac", ["ga_s1_nrb_iw_hh_1"], bbox=BBOX,
                       datetime="2021-01-01/2021-03-01")
grid = sg.grid_from_bbox(BBOX, "EPSG:3031", 200)
groups = sg.group_items(items, "solar_day")
out = sg.stac_load(groups, ["hh_gamma0", "oa_layover_shadow_mask"], grid, overviews=ovr, fuse=fuse)
xl, yb, xr, yt = grid["extent"]
np.savez_compressed(sys.argv[2], hh=out["hh_gamma0"], mask=out["oa_layover_shadow_mask"], time=np.array(list(groups)),
                    gt=np.array([xl, 200, 0.0, yt, 0.0, -200]), shape=np.array([grid["height"], grid["width"]]),
                    item_ids=np.array(sorted(i["id"] for i in items)))
print(f"{len(items)} items, {len(groups)} groups, grid {grid['width']} x {grid['height']}, {time.time() - t0:.1f} s")
