#!/usr/bin/env python3
"""GA tutorial_c1/03_loading_with_stac.ipynb, cells 5-28, as a script (de-sar-sample-data 37f17a5).

Search DEA's STAC for IW HH bursts over an Antarctic AOI, then odc.stac.load them onto a
200 m EPSG:3031 grid grouped by solar day. Saves the arrays for comparison.

  python3 odc_load.py out.npz
"""
import json
import sys
import time

import numpy as np
from odc.geo import BoundingBox
from odc.stac import configure_s3_access, load
from pystac_client import Client

t0 = time.time()
stac_client = Client.open("https://explorer.dev.dea.ga.gov.au/stac")
configure_s3_access(cloud_defaults=True, aws_unsigned=True)
aoi_bbox = BoundingBox(left=73.5, bottom=-69.1, right=74.0, top=-68.8, crs="EPSG:4326")
items = stac_client.search(collections=["ga_s1_nrb_iw_hh_1"], datetime="2021-01-01/2021-03-01",
                           intersects=aoi_bbox.boundary()).item_collection()
print(f"Found {len(items)} items")
t1 = time.time()
ds = load(items=items, bands=["hh_gamma0", "oa_layover_shadow_mask"], intersects=aoi_bbox.boundary(),
          crs="3031", resolution=200, groupby="solar_day", chunks={})
ds = ds.compute()
t2 = time.time()
gb = ds.odc.geobox
print(ds)
np.savez_compressed(sys.argv[1], hh=ds["hh_gamma0"].values, mask=ds["oa_layover_shadow_mask"].values,
                    time=ds.time.values.astype("datetime64[D]").astype(str),
                    gt=np.array(gb.affine.to_gdal()), shape=np.array(gb.shape),
                    item_ids=np.array(sorted(i.id for i in items)))
print(json.dumps(dict(n_items=len(items), shape=list(ds["hh_gamma0"].shape), gt=list(gb.affine.to_gdal()),
                      mask_nodata=str(ds["oa_layover_shadow_mask"].attrs.get("nodata")),
                      search_s=round(t1 - t0, 1), load_s=round(t2 - t1, 1))))
