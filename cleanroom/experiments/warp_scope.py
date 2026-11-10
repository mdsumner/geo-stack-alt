"""Minimal, offline repro: does bilinear/cubic downsampling in the warper honour XSCALE?

Synthetic random raster, warped 2x coarser in the same CRS. For each data type, resampling
and nodata setting, compare default output with XSCALE=YSCALE=1: if identical, the kernel
ignored the downsampling scale (no anti-aliasing).

    python warp_scope.py
"""
import numpy as np
from osgeo import gdal, osr
gdal.UseExceptions()
print("GDAL", gdal.__version__)
rng = np.random.default_rng(1)
arr = rng.uniform(0, 200, (400, 400))
srs = osr.SpatialReference(); srs.ImportFromEPSG(3577)
for dt, name in [(gdal.GDT_Byte, "Byte"), (gdal.GDT_Int16, "Int16"), (gdal.GDT_Float32, "Float32"),
                 (gdal.GDT_Float64, "Float64")]:
    src = gdal.GetDriverByName("MEM").Create("", 400, 400, 1, dt)
    src.SetGeoTransform((0, 10, 0, 4000, 0, -10)); src.SetSpatialRef(srs)
    src.GetRasterBand(1).WriteArray(arr)
    for alg in ["bilinear", "cubic", "lanczos"]:
        for nd in [None, 255]:
            def w(wo):
                kw = dict(format="MEM", xRes=20, yRes=20, resampleAlg=alg, warpOptions=wo)
                if nd is not None: kw["srcNodata"] = nd
                return gdal.Warp("", src, **kw).ReadAsArray().astype("f8")
            a, b = w([]), w(["XSCALE=1", "YSCALE=1"])
            print(f"{name:8s} {alg:9s} srcNodata={str(nd):5s} default==noscale: {np.array_equal(a, b)}"
                  f"  (maxdiff {abs(a-b).max():.3f})")
