"""Bilinear warp with explicit XSCALE/YSCALE values, to test whether computed scales are applied.

    python warp_scales.py outdir tag
"""
import sys
sys.path.insert(0, "/cleanroom/probe")
from osgeo import gdal
from common import CRS, DEM, EXTENT, RES
gdal.UseExceptions()
gdal.SetConfigOption("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
out, tag = sys.argv[1], sys.argv[2]
S = {"default": None, "s1": (1, 1), "s313": (0.588881, 0.746642), "swin": (1000 / 1890, 1000 / 1481)}
for k, s in S.items():
    wo = [] if s is None else [f"XSCALE={s[0]}", f"YSCALE={s[1]}"]
    gdal.Warp(f"{out}/{tag}_{k}.tif", "/vsicurl/" + DEM, format="GTiff", dstSRS=CRS,
              outputBounds=EXTENT, xRes=RES, yRes=RES, resampleAlg="bilinear", warpOptions=wo)
    print(k, wo)
