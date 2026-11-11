#!/usr/bin/env python3
"""The two GDAL behaviours the NormCovar port runs into, on this env's GDAL:
  1. warp with destination nodata 0 rewrites valid 0s as 1 (what odc-geo/rasterio do to the
     reference's uint8 landmask and RGB resamples): the landmask zoomed /10 with near, with and
     without dstNodata=0
  2. gdal_rasterize creating its output sets NoData=0 on it, with or without -init
  python gdal_checks.py <coastline .shp>"""
import json
import sys

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
shp = sys.argv[1]
ext, ts = (275440.0, -1338960.0, 342760.0, -1282680.0), (1683, 1407)   # the EW grid, 40 m, EPSG:3031
out = dict(gdal=gdal.__version__)
for init in (None, 0):
    ds = gdal.Rasterize("/vsimem/new.tif", shp, outputBounds=ext, width=ts[0], height=ts[1], outputType=gdal.GDT_Byte,
                        burnValues=[1], initValues=None if init is None else [init])
    out[f"rasterize_new_output_init_{init}_nodata"] = ds.GetRasterBand(1).GetNoDataValue()
    lm = ds.ReadAsArray()
    ds = None
mem = gdal.Translate("", "/vsimem/new.tif", format="MEM", noData="none")
out["landmask_zeros"] = int((lm == 0).sum())
msgs = []
gdal.PushErrorHandler(lambda cls, no, msg: msgs.append(msg))
for nd in (None, 0):
    msgs.clear()
    r = gdal.Warp("", mem, format="MEM", outputBounds=ext, width=168, height=141, resampleAlg="near",
                  warpOptions=["XSCALE=1", "YSCALE=1"], dstNodata=nd).ReadAsArray()
    out[f"warp_dstnodata_{nd}"] = dict(zeros=int((r == 0).sum()), ones=int((r == 1).sum()), messages=list(msgs))
gdal.PopErrorHandler()
print(json.dumps(out, indent=1))
