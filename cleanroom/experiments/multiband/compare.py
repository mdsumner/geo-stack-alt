#!/usr/bin/env python3
"""odc_visual.py reference vs a stacgrid result (sg_visual.py, or R via r_to_npz.py); and odc's
as-is visual (no raster:bands: float32, no nodata) vs the same load with raster:bands.
  python compare.py ref.npz sg.npz"""
import json
import sys

import numpy as np

a, b = np.load(sys.argv[1]), np.load(sys.argv[2])


def diff(x, y):
    if x.shape != y.shape:
        return dict(shape=[list(x.shape), list(y.shape)])
    d = x.astype("float64") != y.astype("float64")
    return dict(dtype=[str(x.dtype), str(y.dtype)], n_differ=int(d.sum()), of=int(d.size))


rep = dict(same_items=sorted(a["ids"].tolist()) == sorted(b["ids"].tolist()), n_items=[len(a["ids"]), len(b["ids"])],
           same_gt=bool(np.allclose(a["gt"], b["gt"])), labels_equal=a["labels"].tolist() == b["labels"].tolist(),
           bands={n: diff(a[n], b[n]) for n in a["names"]})
x, y = a["asis_visual"], a["visual.1"]
d = x.astype("float64") != y.astype("float64")
rep["odc_asis_vs_raster_bands"] = dict(dtype=[str(x.dtype), str(y.dtype)], n_differ=int(d.sum()), of=int(d.size),
                                       asis_nan_where_0=int((np.isnan(x) & (y == 0)).sum()),
                                       asis_0_where_data=int(((x == 0) & (y != 0)).sum()),
                                       data_values_differ=int((d & ~np.isnan(x) & (y != 0)).sum()),
                                       groups_affected=int(d.reshape(d.shape[0], -1).any(1).sum()), groups=int(d.shape[0]))
print(json.dumps(rep, indent=1))
