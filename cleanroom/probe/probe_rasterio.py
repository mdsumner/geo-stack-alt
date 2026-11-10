"""Probe the wheel stack: rasterio (and pyogrio, via geopandas) as a newcomer would have it.

Same job as probe_gdal.py: warp the Copernicus DEM COG to a 40 km Albers box at 40 m.
Also records which GDAL each wheel bundles, and how many libgdal copies one process loads.

    python probe_rasterio.py out.json
"""
import json
import sys
import time

import numpy as np

from common import CRS, DEM, DRIVERS, EXTENT, RES, loaded_libs, summarise

res = {"lang": "python", "binding": "rasterio", "python": sys.version.split()[0]}

import rasterio  # noqa: E402
from rasterio.transform import from_origin  # noqa: E402
from rasterio.warp import Resampling, reproject  # noqa: E402

res["rasterio"] = rasterio.__version__
res["gdal_rasterio"] = rasterio.__gdal_version__
with rasterio.Env() as env:
    have = set(env.drivers())
res["driver_count"] = len(have)
res["drivers"] = {d: d in have for d in DRIVERS}

t0 = time.time()
xmin, ymin, xmax, ymax = EXTENT
nx, ny = int((xmax - xmin) / RES), int((ymax - ymin) / RES)
dst = np.zeros((ny, nx), dtype="float32")
with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR"):
    with rasterio.open(DEM) as src:
        nodata = src.nodata if src.nodata is not None else -32767.0
        dst[:] = nodata
        reproject(rasterio.band(src, 1), dst, dst_transform=from_origin(xmin, ymax, RES, RES),
                  dst_crs=CRS, dst_nodata=nodata, resampling=Resampling.bilinear)
res["warp_seconds"] = round(time.time() - t0, 2)
res["warp"] = summarise(dst, nodata)
res["libs_after_rasterio"] = loaded_libs()

# geopandas brings pyogrio, a second wheel with its own GDAL.
try:
    import pyogrio
    res["pyogrio"] = pyogrio.__version__
    res["gdal_pyogrio"] = pyogrio.__gdal_version_string__
    pyogrio.list_drivers()
except Exception as e:  # noqa: BLE001
    res["pyogrio"] = f"failed: {e}"
res["libs_after_pyogrio"] = loaded_libs()
res["libgdal_copies"] = len([p for p in res["libs_after_pyogrio"] if "libgdal" in p])

json.dump(res, open(sys.argv[1], "w"), indent=2)
print(json.dumps(res, indent=2))
