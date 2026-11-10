"""Warp the probe DEM with osgeo.gdal and save it, for cross-version comparison.

    python warp_one.py out.tif
"""
import sys
sys.path.insert(0, "/cleanroom/probe")
from osgeo import gdal
from common import CRS, DEM, EXTENT, RES, summarise
gdal.UseExceptions()
gdal.SetConfigOption("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")
src = gdal.Open("/vsicurl/" + DEM)
b = src.GetRasterBand(1)
print("gdal", gdal.__version__, "src", src.RasterXSize, src.RasterYSize, b.DataType,
      "nodata", b.GetNoDataValue(), "ovr", b.GetOverviewCount(),
      [ (b.GetOverview(i).XSize) for i in range(b.GetOverviewCount())])
ds = gdal.Warp(sys.argv[1], src, format="GTiff", dstSRS=CRS, outputBounds=EXTENT,
               xRes=RES, yRes=RES, resampleAlg="bilinear")
print(summarise(ds.ReadAsArray(), ds.GetRasterBand(1).GetNoDataValue()))
