"""Probe an osgeo.gdal install: versions, drivers, which libgdal is loaded, and one real job.

The job: warp a Copernicus 30 m DEM COG (read over HTTPS with /vsicurl/) to a 40 km box in
Australian Albers (EPSG:3577) at 40 m, and summarise it. probe.R does the same job in R, so the
numbers can be compared.

    python probe_gdal.py out.json
"""
import json
import sys
import time

from osgeo import gdal, osr

from common import DEM, DRIVERS, EXTENT, RES, CRS, loaded_libs, summarise

gdal.UseExceptions()
gdal.SetConfigOption("GDAL_DISABLE_READDIR_ON_OPEN", "EMPTY_DIR")

res = {
    "lang": "python",
    "binding": "osgeo.gdal",
    "python": sys.version.split()[0],
    "gdal": gdal.__version__,
    "proj": ".".join(str(f()) for f in (osr.GetPROJVersionMajor, osr.GetPROJVersionMinor,
                                        osr.GetPROJVersionMicro)),
}
have = {gdal.GetDriver(i).ShortName for i in range(gdal.GetDriverCount())}
res["driver_count"] = len(have)
res["drivers"] = {d: d in have for d in DRIVERS}

t0 = time.time()
ds = gdal.Warp("", "/vsicurl/" + DEM, format="MEM", dstSRS=CRS, outputBounds=EXTENT,
               xRes=RES, yRes=RES, resampleAlg="bilinear")
arr = ds.ReadAsArray()
res["warp_seconds"] = round(time.time() - t0, 2)
res["warp"] = summarise(arr, ds.GetRasterBand(1).GetNoDataValue())

# The GDAL CLI as a Python API (GDAL >= 3.11).
try:
    alg = gdal.Run("raster", "info", input="/vsicurl/" + DEM, output_format="json")
    res["gdal_run"] = "ok: " + str(alg.Output()["size"])
except Exception as e:  # noqa: BLE001
    res["gdal_run"] = f"failed: {e}"

res["libs"] = loaded_libs()
json.dump(res, open(sys.argv[1], "w"), indent=2)
print(json.dumps(res, indent=2))
