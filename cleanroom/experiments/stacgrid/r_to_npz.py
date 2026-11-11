#!/usr/bin/env python3
"""Pack ga_r.R's GeoTIFFs into the npz layout compare.py reads.  python3 r_to_npz.py <dir> out.npz"""
import sys
from pathlib import Path

import numpy as np
from osgeo import gdal

gdal.UseExceptions()
d = Path(sys.argv[1])
hh, mask = gdal.Open(str(d / "hh_gamma0.tif")), gdal.Open(str(d / "oa_layover_shadow_mask.tif"))
np.savez_compressed(sys.argv[2], hh=hh.ReadAsArray(), mask=mask.ReadAsArray(),
                    time=np.array([hh.GetRasterBand(b + 1).GetDescription() for b in range(hh.RasterCount)]),
                    gt=np.array(hh.GetGeoTransform()), shape=np.array([hh.RasterYSize, hh.RasterXSize]),
                    item_ids=np.array((d / "item_ids.txt").read_text().split()))
