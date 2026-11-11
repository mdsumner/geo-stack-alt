#!/usr/bin/env python3
"""Pack sg_s2.R outputs like sg_s2.py's npz.  python r_to_npz.py <outdir> out.npz"""
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
d, out = Path(sys.argv[1]), {}
for k in ("raw", "scaled"):
    ds = gdal.Open(str(d / f"{k}.tif"))
    out[k] = ds.ReadAsArray().reshape(ds.RasterCount, ds.RasterYSize, ds.RasterXSize)
    out["labels"] = np.array([ds.GetRasterBand(i + 1).GetDescription() for i in range(ds.RasterCount)])
    out["gt"] = np.array(ds.GetGeoTransform())
out["ids"] = np.array((d / "ids.txt").read_text().split())
np.savez_compressed(sys.argv[2], **out)
