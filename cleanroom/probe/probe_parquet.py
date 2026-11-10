"""Read a remote STAC-GeoParquet index with GDAL's Parquet driver (osgeo.ogr).

The DEA EW Sentinel-1 index from ga-sar-ice (190 scenes, 2019-01 to 2026-05, as of 2026-11-09).

    python probe_parquet.py out.json
"""
import json
import sys
import time

from osgeo import gdal, ogr

gdal.UseExceptions()
URL = ("https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/"
       "pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet")
res = {"gdal": gdal.__version__, "url": URL}
t0 = time.time()
try:
    ds = ogr.Open("/vsicurl/" + URL)
    lyr = ds.GetLayer(0)
    res["driver"] = ds.GetDriver().GetName()
    res["features"] = lyr.GetFeatureCount()
    res["fields"] = lyr.GetLayerDefn().GetFieldCount()
    res["geom_type"] = ogr.GeometryTypeToName(lyr.GetGeomType())
    res["extent"] = [round(v, 3) for v in lyr.GetExtent()]
    f = lyr.GetNextFeature()
    res["first_id"] = f.GetField("id") if f.GetFieldIndex("id") >= 0 else None
except Exception as e:  # noqa: BLE001
    res["error"] = str(e)
res["seconds"] = round(time.time() - t0, 2)
json.dump(res, open(sys.argv[1], "w"), indent=2)
print(json.dumps(res, indent=2))
