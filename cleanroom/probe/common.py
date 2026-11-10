"""Shared constants and helpers for the Python probes (keep in step with probe.R)."""
import re

import numpy as np

DEM = ("https://copernicus-dem-30m.s3.amazonaws.com/"
       "Copernicus_DSM_COG_10_S43_00_E146_00_DEM/Copernicus_DSM_COG_10_S43_00_E146_00_DEM.tif")
CRS = "EPSG:3577"
EXTENT = (1204000, -4735000, 1244000, -4695000)  # xmin, ymin, xmax, ymax: 40 km, central Tas
RES = 40

# Drivers that matter for EO and data work beyond GeoTIFF.
DRIVERS = ["GTiff", "COG", "VRT", "netCDF", "HDF5", "Zarr", "Parquet", "GPKG", "FlatGeobuf",
           "GeoJSON", "ESRI Shapefile", "JP2OpenJPEG", "KEA", "PDF", "STACIT", "GTI",
           "PostgreSQL", "OpenFileGDB", "LIBKML", "WMS", "WMTS"]


def summarise(arr, nodata):
    a = arr.astype("float64")
    ok = np.isfinite(a) if nodata is None else (a != nodata) & np.isfinite(a)
    v = a[ok]
    return {"shape": list(arr.shape), "valid": int(ok.sum()),
            "min": round(float(v.min()), 3), "max": round(float(v.max()), 3),
            "mean": round(float(v.mean()), 4)}


def loaded_libs():
    """Paths of the GDAL/PROJ/GEOS shared libraries in this process."""
    libs = set()
    for line in open("/proc/self/maps"):
        p = line.split()[-1]
        if re.search(r"lib(gdal|proj|geos_c|geos)[.-]", p):
            libs.add(p)
    return sorted(libs)
