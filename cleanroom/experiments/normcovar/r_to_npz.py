#!/usr/bin/env python3
"""Pack nc_r.R outputs like nc_gdal.py's npz.  python r_to_npz.py <outdir> out.npz"""
import json
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
d = Path(sys.argv[1])


def rd(name):
    ds = gdal.Open(str(d / name))
    return ds.ReadAsArray().reshape(ds.RasterCount, ds.RasterYSize, ds.RasterXSize), np.array(ds.GetGeoTransform())


f, gt = rd("float.tif")
rgb_res, gt_res = rd("rgb_resampled.tif")
p = json.loads((d / "pair.json").read_text())
lm_res, _ = rd("landmask_resampled.tif")
np.savez_compressed(sys.argv[2], img1=f[0], img2=f[1], normcovar_11=f[2], normcovar_21=f[3], normcovar_33=f[4],
                    gt=gt, gt_resampled=gt_res, pair=np.array(p["pair"]), n_pairs=p["n_pairs"], times=np.array(p["times"]),
                    rgb=rd("rgb.tif")[0],
                    rgb_resampled=rgb_res, landmask=rd("landmask.tif")[0][0], landmask_resampled=lm_res[0],
                    rgb_landmasked=rd("rgb_landmasked.tif")[0], rgb_resampled_landmasked=rd("rgb_resampled_landmasked.tif")[0])
