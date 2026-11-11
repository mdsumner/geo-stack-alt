#!/usr/bin/env bash
# GA tutorial load (odc-stac) vs the same load in osgeo.gdal, on one libgdal.
# odc-stac isn't packaged in apt, so it goes in a venv that sees apt's rasterio and numpy
# (--system-site-packages): both loads then use Ubuntu's libgdal 3.8.4.
# numpy<2: without it pip installs numpy 2.x into the venv and apt rasterio (numpy 1.26 ABI) fails to import.
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments/ga-sar-ice
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates python3-gdal python3-numpy python3-rasterio python3-venv python3-pip'
step venv bash -c 'python3 -m venv --system-site-packages /venv && /venv/bin/pip install -q "numpy<2" "odc-stac[botocore]>=0.5.2,<0.6" "pystac-client>=0.9,<0.10" && /venv/bin/pip list 2>/dev/null'
/venv/bin/pip list 2>/dev/null > /out/venv-pip-list.txt
step versions /venv/bin/python -c 'from osgeo import gdal; import rasterio, numpy, odc.stac, odc.geo, xarray; print("gdal", gdal.__version__, "rasterio", rasterio.__version__, rasterio.__gdal_version__, "numpy", numpy.__version__, "odc-stac", odc.stac.__version__, "odc-geo", odc.geo.__version__, "xarray", xarray.__version__)'
step odc /venv/bin/python $X/odc_load.py /out/odc.npz
step gdal python3 $X/gdal_load.py /out/gdal.npz
step compare python3 $X/compare.py /out/odc.npz /out/gdal.npz
cat /out/compare.log
