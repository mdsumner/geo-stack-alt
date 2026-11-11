#!/usr/bin/env bash
# GA tutorial load (odc-stac) vs the same load in osgeo.gdal, on one libgdal.
# odc-stac isn't packaged in apt, so it goes in a venv that sees apt's rasterio and numpy
# (--system-site-packages): both loads then use Ubuntu's libgdal 3.8.4.
# numpy pinned to apt's: otherwise pip puts a newer numpy in the venv and apt rasterio fails to import
# (seen on 24.04: numpy 2.5 over apt's 1.26).
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments/ga-sar-ice
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates python3-gdal python3-numpy python3-rasterio python3-venv python3-pip'
export NPV=$(python3 -c "import numpy; print(numpy.__version__)")
step venv bash -c 'python3 -m venv --system-site-packages /venv && /venv/bin/pip install -q "numpy==$NPV" "odc-stac[botocore]>=0.5.2,<0.6" "pystac-client>=0.9,<0.10" && /venv/bin/pip list 2>/dev/null'
/venv/bin/pip list 2>/dev/null > /out/venv-pip-list.txt
step versions /venv/bin/python -c 'from osgeo import gdal; import rasterio, numpy, odc.stac, odc.geo, xarray; print("gdal", gdal.__version__, "rasterio", rasterio.__version__, rasterio.__gdal_version__, "numpy", numpy.__version__, "odc-stac", odc.stac.__version__, "odc-geo", odc.geo.__version__, "xarray", xarray.__version__)'
step odc /venv/bin/python $X/odc_load.py /out/odc.npz
step gdal python3 $X/gdal_load.py /out/gdal.npz
step stacit python3 $X/stacit_load.py /out/stacit.npz
step compare python3 $X/compare.py /out/odc.npz /out/gdal.npz
step compare_stacit python3 $X/compare.py /out/odc.npz /out/stacit.npz
# is the STACIT difference only overview choice? the direct warp again without overviews
step gdal_noovr env GDAL_LOAD_OVR=NONE python3 $X/gdal_load.py /out/gdal_noovr.npz
step compare_noovr_stacit python3 $X/compare.py /out/gdal_noovr.npz /out/stacit.npz
step compare_odc_noovr python3 $X/compare.py /out/odc.npz /out/gdal_noovr.npz
# and is the rest overlap order? STACIT's VRT lets the last source win
step gdal_noovr_last env GDAL_LOAD_OVR=NONE GDAL_LOAD_FUSE=last python3 $X/gdal_load.py /out/gdal_noovr_last.npz
step compare_noovr_last_stacit python3 $X/compare.py /out/gdal_noovr_last.npz /out/stacit.npz
tail -n 3 /out/stacit.log
