#!/usr/bin/env python3
"""Pack sg_*.R outputs (<stack>.tif, <stack>_ids.txt) into an npz like sg_*.py's.
  python r_to_npz.py <outdir> out.npz <stack> [<stack> ...]"""
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
d, out = Path(sys.argv[1]), {}
for k in sys.argv[3:]:
    ds = gdal.Open(str(d / f"{k}.tif"))
    out[k] = ds.ReadAsArray().reshape(ds.RasterCount, ds.RasterYSize, ds.RasterXSize)
    out[f"{k}_time"] = np.array([ds.GetRasterBand(i + 1).GetDescription() for i in range(ds.RasterCount)])
    out[f"{k}_gt"] = np.array(ds.GetGeoTransform())
    out[f"{k}_ids"] = np.array((d / f"{k}_ids.txt").read_text().split())
np.savez_compressed(sys.argv[2], **out)
