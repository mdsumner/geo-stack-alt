#!/usr/bin/env python3
"""rasterio.warp.reproject of a uint8 0/1 image (left half 0, right half 1) 100x100 -> 10x10, nearest,
XSCALE=YSCALE=1, no source nodata, destination nodata None and 0: what odc-geo's xr_reproject asks
of rasterio for the NormCovar landmask (it passes its fill value 0 as dst_nodata).
  python rio_checks.py"""
import json

import numpy as np
import rasterio
import rasterio.warp
from rasterio.transform import from_origin

src = np.zeros((100, 100), "uint8")
src[:, 50:] = 1
out = dict(rasterio=rasterio.__version__, gdal=rasterio.__gdal_version__)
for nd in (None, 0):
    dst = np.zeros((10, 10), "uint8")
    rasterio.warp.reproject(src, dst, src_transform=from_origin(0, 100, 1, 1), dst_transform=from_origin(0, 100, 10, 10),
                            src_crs="EPSG:3031", dst_crs="EPSG:3031", resampling=rasterio.warp.Resampling.nearest,
                            src_nodata=None, dst_nodata=nd, XSCALE=1, YSCALE=1)
    out[f"dst_nodata_{nd}"] = dict(zeros=int((dst == 0).sum()), ones=int((dst == 1).sum()))
print(json.dumps(out))
