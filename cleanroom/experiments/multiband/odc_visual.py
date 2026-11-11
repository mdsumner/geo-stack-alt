#!/usr/bin/env python3
"""Reference for multi-band assets: Earth Search sentinel-2-l2a "visual" (TCI.tif, 3 bands uint8,
nodata 0 in the file) west of Hobart across the 55GDN/55GEN tile overlap, Dec 2021 - Feb 2022.

The visual asset describes its bands in eo:bands only; odc-stac 0.5.3 counts bands from
raster:bands or STAC 1.1 bands, so it sees one band, float32, no nodata:
  asis_visual   load(items, bands=["visual"])   band 1, every pixel valid (0s included)
  (visual.2 / visual.3 -> KeyError)
With raster:bands added to each item ([{"nodata": 0, "data_type": "uint8"}] * 3):
  visual.1 visual.2 visual.3 visual red   one load, solar_day groups
  python odc_visual.py out.npz"""
import copy
import json
import sys
import time

import numpy as np
from odc.stac import configure_s3_access, load
from pystac_client import Client

configure_s3_access(aws_unsigned=True)
BBOX = (147.0, -42.9, 147.35, -42.85)
NAMES = ["visual.1", "visual.2", "visual.3", "visual", "red"]
t0 = time.time()
items = list(Client.open("https://earth-search.aws.element84.com/v1").search(
    collections=["sentinel-2-l2a"], bbox=BBOX, datetime="2021-12-01/2022-03-01").items())
kw = dict(crs="EPSG:32755", resolution=10, bbox=BBOX, groupby="solar_day")
asis = load(items, bands=["visual"], **kw)
errs = {}
for b in ("visual.2", "visual.3"):
    try:
        load(items, bands=[b], **kw)
    except Exception as e:  # noqa: BLE001
        errs[b] = f"{type(e).__name__}: {e}"
patched = copy.deepcopy(items)
for it in patched:
    it.assets["visual"].extra_fields["raster:bands"] = [{"nodata": 0, "data_type": "uint8"}] * 3
ds = load(patched, bands=NAMES, **kw)
a = ds.odc.geobox.affine
out = {n: ds[n].values for n in NAMES}
np.savez_compressed(sys.argv[1], asis_visual=asis["visual"].values, names=np.array(NAMES),
                    gt=np.array([a.c, a.a, a.b, a.f, a.d, a.e]),
                    labels=np.array([str(t)[:10] for t in ds.time.values]),
                    ids=np.array([it.id for it in items]), **out)
print(json.dumps(dict(items=len(items), groups=ds.sizes["time"], shape=list(ds["visual.1"].shape),
                      asis=dict(dtype=str(asis["visual"].dtype), nodata=str(asis["visual"].attrs.get("nodata"))),
                      patched={n: dict(dtype=str(ds[n].dtype), nodata=str(ds[n].attrs.get("nodata"))) for n in NAMES},
                      errors=errs, tiles=sorted({it.properties.get("grid:code") for it in items}),
                      s=round(time.time() - t0, 1))))
