"""Offline repro, part 2: which condition makes the warper ignore XSCALE (bilinear, Float32)?
Varies the downsampling factor (same CRS) and adds reprojection (EPSG:4326 -> EPSG:3577).

    python warp_scope2.py
"""
import numpy as np
from osgeo import gdal, osr
gdal.UseExceptions()
print("GDAL", gdal.__version__)
arr = np.random.default_rng(1).uniform(0, 200, (1000, 1000)).astype("float32")

def mk(epsg, gt):
    s = osr.SpatialReference(); s.ImportFromEPSG(epsg)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    d = gdal.GetDriverByName("MEM").Create("", 1000, 1000, 1, gdal.GDT_Float32)
    d.SetGeoTransform(gt); d.SetSpatialRef(s); d.GetRasterBand(1).WriteArray(arr)
    return d

proj = mk(3577, (0, 10, 0, 10000, 0, -10))
geog = mk(4326, (146.0, 0.0002777777777777778, 0, -42.0, 0, -0.0002777777777777778))

cases = []
for res in [12.5, 15, 17.5, 20, 25, 40]:
    cases.append((f"same CRS, 10 -> {res} m", proj, dict(xRes=res, yRes=res)))
for res in [25, 40, 60]:
    cases.append((f"4326 -> 3577, ~23x31 -> {res} m", geog, dict(dstSRS="EPSG:3577", xRes=res, yRes=res)))
cases.append(("4326 -> 3577, sub-window 40 m", geog,
              dict(dstSRS="EPSG:3577", xRes=40, yRes=40,
                   outputBounds=(1204000 + 4000, -4735000 + 25000, 1204000 + 14000, -4735000 + 35000))))
for label, src, kw in cases:
    a = gdal.Warp("", src, format="MEM", resampleAlg="bilinear", **kw).ReadAsArray().astype("f8")
    b = gdal.Warp("", src, format="MEM", resampleAlg="bilinear", warpOptions=["XSCALE=1", "YSCALE=1"],
                  **kw).ReadAsArray().astype("f8")
    ok = np.isfinite(a) & np.isfinite(b)
    print(f"{label:34s} shape={a.shape}  scale-ignored={np.array_equal(a[ok], b[ok])}")
