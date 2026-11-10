"""Warp variants to isolate the GDAL 3.12 -> 3.13 difference. Writes one tif per variant.

    python warp_variants.py outdir tag
"""
import json, sys
sys.path.insert(0, "/cleanroom/probe")
from osgeo import gdal
from common import CRS, DEM, EXTENT, RES
gdal.UseExceptions()
gdal.SetConfigOption("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
out, tag = sys.argv[1], sys.argv[2]
src = gdal.Open("/vsicurl/" + DEM)
print(tag, "src geotransform", src.GetGeoTransform(), src.GetMetadataItem("AREA_OR_POINT"))
V = {
    "near": dict(resampleAlg="near"),
    "bilinear": dict(resampleAlg="bilinear"),
    "bilinear_noscale": dict(resampleAlg="bilinear", warpOptions=["XSCALE=1", "YSCALE=1"]),
    "cubic": dict(resampleAlg="cubic"),
    "average": dict(resampleAlg="average"),
    "bilinear_pointignore": dict(resampleAlg="bilinear"),
}
for k, o in V.items():
    gdal.SetConfigOption("GTIFF_POINT_GEO_IGNORE", "YES" if k.endswith("pointignore") else None)
    s = gdal.Open("/vsicurl/" + DEM)
    gdal.Warp(f"{out}/{tag}_{k}.tif", s, format="GTiff", dstSRS=CRS, outputBounds=EXTENT,
              xRes=RES, yRes=RES, **o)
    print(k, "ok")
