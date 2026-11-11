#!/usr/bin/env python3
"""The odc_visual.py load with stacgrid.py.  python sg_visual.py <stacgrid dir> out.npz"""
import json
import sys
import time

import numpy as np

sys.path.insert(0, sys.argv[1])
import stacgrid as sg  # noqa: E402

BBOX = (147.0, -42.9, 147.35, -42.85)
NAMES = ["visual.1", "visual.2", "visual.3", "visual", "red"]
t0 = time.time()
items = sg.stac_search("https://earth-search.aws.element84.com/v1", ["sentinel-2-l2a"], bbox=BBOX,
                       datetime="2021-12-01/2022-03-01")
grid = sg.grid_from_bbox(BBOX, "EPSG:32755", 10)
groups = sg.group_items(items, "solar_day", grid=grid)
out = sg.stac_load(groups, NAMES, grid)
xl, yb, xr, yt = grid["extent"]
np.savez_compressed(sys.argv[2], names=np.array(NAMES), gt=np.array([xl, 10, 0.0, yt, 0.0, -10]),
                    labels=np.array(list(groups)), ids=np.array([i["id"] for i in items]), **out)
print(json.dumps(dict(items=len(items), groups=len(groups), shape=list(out["visual.1"].shape),
                      dtypes={n: str(v.dtype) for n, v in out.items()}, s=round(time.time() - t0, 1))))
