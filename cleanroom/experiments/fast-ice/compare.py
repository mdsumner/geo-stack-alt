#!/usr/bin/env python3
"""Compare two fast-ice load results (odc_*.py vs sg_*.py), stack by stack.
  python compare.py a.npz b.npz <stack> [<stack> ...]     e.g. ew iw, or api pq"""
import json
import sys

import numpy as np

a, b = np.load(sys.argv[1]), np.load(sys.argv[2])
rep = {}
for k in sys.argv[3:]:
    r = dict(same_items=sorted(a[f"{k}_ids"].tolist()) == sorted(b[f"{k}_ids"].tolist()),
             n_items=[len(a[f"{k}_ids"]), len(b[f"{k}_ids"])], shape=[list(a[k].shape), list(b[k].shape)],
             time=[a[f"{k}_time"].tolist(), b[f"{k}_time"].tolist()])
    gt = lambda z: z[f"{k}_gt"] if f"{k}_gt" in z else z["gt"]  # noqa: E731
    r["same_gt"] = bool(np.allclose(gt(a), gt(b)))
    if a[k].shape == b[k].shape:
        x, y = a[k].astype("float64"), b[k].astype("float64")
        fx, fy = np.isfinite(x), np.isfinite(y)
        both = fx & fy
        d = np.abs(x[both] - y[both])
        r.update(n_finite=[int(fx.sum()), int(fy.sum())], finite_disagree=int((fx != fy).sum()),
                 n_differ=int((d > 0).sum()), of=int(both.sum()), max_abs=float(d.max()) if d.size else 0.0,
                 per_group_differ=[int(((np.abs(x[i] - y[i]) > 0) & both[i]).sum() + (fx[i] != fy[i]).sum())
                                   for i in range(x.shape[0])])
    else:
        r["ids_only_a"] = sorted(set(a[f"{k}_ids"].tolist()) - set(b[f"{k}_ids"].tolist()))
        r["ids_only_b"] = sorted(set(b[f"{k}_ids"].tolist()) - set(a[f"{k}_ids"].tolist()))
    rep[k] = r
print(json.dumps(rep, indent=1))
