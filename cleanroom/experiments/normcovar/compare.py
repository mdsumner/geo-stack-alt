#!/usr/bin/env python3
"""nc_ref.py vs a port (nc_gdal.py, or nc_r.R via r_to_npz.py), product by product.
Times are compared to the second (the reference prints numpy datetimes, the ports ISO strings).
  python compare.py ref.npz port.npz"""
import json
import sys

import numpy as np

a, b = np.load(sys.argv[1]), np.load(sys.argv[2])
day = lambda s: [str(x).replace("T", " ").replace("Z", "")[:19] for x in s]  # noqa: E731
rep = dict(n_pairs=[int(a["n_pairs"]), int(b["n_pairs"])], pair=[day(a["pair"]), day(b["pair"])],
           same_times=day(a["times"]) == day(b["times"]), same_gt=bool(np.allclose(a["gt"], b["gt"])),
           same_gt_resampled=bool(np.allclose(a["gt_resampled"], b["gt_resampled"], rtol=0, atol=1e-6)),
           gt_resampled=[a["gt_resampled"].tolist(), b["gt_resampled"].tolist()])
for k in ("img1", "img2", "normcovar_11", "normcovar_21", "normcovar_33", "rgb", "rgb_resampled", "landmask",
          "landmask_resampled", "rgb_landmasked", "rgb_resampled_landmasked"):
    x, y = a[k], b[k]
    if x.shape != y.shape:
        rep[k] = dict(shape=[list(x.shape), list(y.shape)])
        continue
    x64, y64 = x.astype("float64"), y.astype("float64")
    fx, fy = np.isfinite(x64), np.isfinite(y64)
    both = fx & fy
    d = np.abs(x64[both] - y64[both])
    rep[k] = dict(dtype=[str(x.dtype), str(y.dtype)], shape=list(x.shape), n_differ=int((d > 0).sum()),
                  nonfinite_disagree=int((fx != fy).sum()), max_abs=float(d.max()) if d.size else 0.0)
    if x.dtype == np.uint8:
        rep[k]["n_differ_by_more_than_1"] = int((d > 1).sum())
print(json.dumps(rep, indent=1))
