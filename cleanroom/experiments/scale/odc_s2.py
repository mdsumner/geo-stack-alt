#!/usr/bin/env python3
"""Reference for raster:bands scale/offset: Earth Search sentinel-2-l2a red, near Hobart, across the
change of processing baseline (offset 0 before 04.00, -0.1 from 04.00; reprocessed duplicates).

  raw        odc.stac.load(..., groupby="solar_day"): stored values (odc-stac 0.5 ignores scale/offset)
  scaled     odc loads each item alone (groupby="id"), each scaled with its own raster:bands
             scale/offset in float64 -> float32, NaN for nodata, then merged first-valid in (time, id)
             order within odc's solar-day groups (grid-centre longitude, whole hours)
  naive_*    raw, then one scale/offset for the whole stack (offset -0.1, and 0)
  python odc_s2.py out.npz"""
import json
import sys
import time

import numpy as np
from odc.stac import configure_s3_access, load
from pystac_client import Client

configure_s3_access(aws_unsigned=True)
BBOX = (147.3, -42.9, 147.35, -42.85)
t0 = time.time()
items = list(Client.open("https://earth-search.aws.element84.com/v1").search(
    collections=["sentinel-2-l2a"], bbox=BBOX, datetime="2021-12-01/2022-03-01").items())
kw = dict(bands=["red"], crs="EPSG:32755", resolution=10, bbox=BBOX)
raw = load(items, groupby="solar_day", **kw)
each = load(items, groupby="id", **kw)   # one layer per item, in input order
assert each.sizes["time"] == len(items)

# odc's solar-day groups: one longitude (output grid centre), whole hours
((lon, _),) = raw.odc.geobox.extent.centroid.to_crs("epsg:4326").points
import datetime as dt  # noqa: E402
solar = [(it.datetime + dt.timedelta(hours=int(lon / 15))).date().isoformat() for it in items]
order = sorted(range(len(items)), key=lambda i: (items[i].datetime, items[i].id))  # as odc-stac
labels = sorted(set(solar))
scaled = np.full((len(labels), *raw.red.shape[1:]), np.nan, dtype="float32")
offsets = []
for i in order:
    b = items[i].assets["red"].extra_fields["raster:bands"][0]
    sc, of = float(b.get("scale", 1)), float(b.get("offset", 0))
    offsets.append(of)
    v = each.red.values[i]
    a = (v.astype("float64") * sc + of).astype("float32")
    a[v == 0] = np.nan
    g = scaled[labels.index(solar[i])]
    take = np.isnan(g) & ~np.isnan(a)
    g[take] = a[take]
r = raw.red.values
naive = {}
for of in (-0.1, 0.0):
    x = (r.astype("float64") * 0.0001 + of).astype("float32")
    x[r == 0] = np.nan
    naive[of] = x
a = raw.odc.geobox.affine
np.savez_compressed(sys.argv[1], raw=r, scaled=scaled, naive_m01=naive[-0.1], naive_0=naive[0.0],
                    gt=np.array([a.c, a.a, a.b, a.f, a.d, a.e]), labels=np.array(labels),
                    ids=np.array([it.id for it in items]),
                    baselines=np.array([str(it.properties.get("s2:processing_baseline")) for it in items]))
print(json.dumps(dict(items=len(items), groups=len(labels), shape=r.shape, lon=lon, s=round(time.time() - t0, 1),
                      offsets=sorted(set(offsets)),
                      groups_mixing_offsets=sum(len({float(items[i].assets["red"].extra_fields["raster:bands"][0].get("offset", 0))
                                                     for i in range(len(items)) if solar[i] == l}) > 1 for l in labels))))
