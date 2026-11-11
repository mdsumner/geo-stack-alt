#!/usr/bin/env python3
"""odc_s2.py reference vs a stacgrid result (Python sg_s2.py, or R via r_to_npz.py).
  python compare.py ref.npz sg.npz"""
import json
import sys

import numpy as np

a, b = np.load(sys.argv[1]), np.load(sys.argv[2])


def diff(x, y):
    if x.shape != y.shape:
        return dict(shape=[list(x.shape), list(y.shape)])
    x, y = x.astype("float64"), y.astype("float64")
    fx, fy = np.isfinite(x), np.isfinite(y)
    if np.issubdtype(a["raw"].dtype, np.integer) and x is not None:
        pass
    both = fx & fy
    d = np.abs(x[both] - y[both])
    return dict(finite=[int(fx.sum()), int(fy.sum())], finite_disagree=int((fx != fy).sum()),
                n_differ=int((d > 0).sum()), of=int(both.sum()), max_abs=float(d.max()) if d.size else 0.0)


rep = dict(same_items=sorted(a["ids"].tolist()) == sorted(b["ids"].tolist()), n_items=[len(a["ids"]), len(b["ids"])],
           same_gt=bool(np.allclose(a["gt"], b["gt"])), labels_equal=a["labels"].tolist() == b["labels"].tolist(),
           raw=diff(a["raw"], b["raw"]), scaled=diff(a["scaled"], b["scaled"]),
           naive_offset_m01_vs_scaled=diff(a["naive_m01"], b["scaled"]),
           naive_offset_0_vs_scaled=diff(a["naive_0"], b["scaled"]))
print(json.dumps(rep, indent=1))
