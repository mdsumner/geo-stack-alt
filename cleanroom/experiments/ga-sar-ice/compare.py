#!/usr/bin/env python3
"""Compare odc_load.py and gdal_load.py outputs.  python3 compare.py odc.npz gdal.npz"""
import json
import sys

import numpy as np

a, b = np.load(sys.argv[1]), np.load(sys.argv[2])
rep = dict(same_items=bool(np.array_equal(a["item_ids"], b["item_ids"])), n_items=[len(a["item_ids"]), len(b["item_ids"])],
           time=[list(a["time"]), list(b["time"])], gt=[list(a["gt"]), list(b["gt"])],
           shape=[list(a["hh"].shape), list(b["hh"].shape)])
# odc labels a group by its first item's UTC time, gdal_load by solar date: compare groups by position
if a["hh"].shape == b["hh"].shape:
    for k in ("hh", "mask"):
        x, y = a[k].astype("float64"), b[k].astype("float64")
        fx, fy = np.isfinite(x), np.isfinite(y)
        both = fx & fy
        d = np.abs(x[both] - y[both])
        rep[k] = dict(n_finite=[int(fx.sum()), int(fy.sum())], finite_disagree=int((fx != fy).sum()),
                      n_differ=int((d > 0).sum()), of=int(both.sum()), max_abs=float(d.max()) if d.size else 0.0,
                      dtype=[str(a[k].dtype), str(b[k].dtype)],
                      per_time_differ=[int((np.abs(x[i] - y[i])[both[i]] > 0).sum()) for i in range(x.shape[0])])
print(json.dumps(rep, indent=1))
