#!/usr/bin/env bash
# stacgrid.py and stacgrid.R against odc-stac on the GA tutorial load, one libgdal (Ubuntu apt).
# Python: python3-gdal. R: r2u (gdalraster, jsonlite). odc-stac: venv over apt rasterio/numpy.
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments
SG=/stacgrid  # mount: MOUNT=$PWD/stacgrid:/stacgrid:ro
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates python3-gdal python3-numpy python3-rasterio python3-venv python3-pip'
export NPV=$(python3 -c "import numpy; print(numpy.__version__)")
step venv bash -c 'python3 -m venv --system-site-packages /venv && /venv/bin/pip install -q "numpy==$NPV" "odc-stac[botocore]>=0.5.2,<0.6" "pystac-client>=0.9,<0.10"'
step r2u_setup bash -c "curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash"
step r_install Rscript -e 'install.packages(c("gdalraster", "jsonlite")); cat("gdalraster", format(packageVersion("gdalraster")), gdalraster::gdal_version()[1], "\n")'
step odc /venv/bin/python $X/ga-sar-ice/odc_load.py /out/odc.npz
step sg_py python3 $X/stacgrid/ga_py.py $SG /out/sg_py.npz
step sg_r bash -c "Rscript $X/stacgrid/ga_r.R $SG /out/sg_r && python3 $X/stacgrid/r_to_npz.py /out/sg_r /out/sg_r.npz"
step sg_py_stacit python3 $X/stacgrid/ga_py.py $SG /out/sg_py_stacit.npz NONE last
step sg_r_stacit bash -c "Rscript $X/stacgrid/ga_r.R $SG /out/sg_r_stacit NONE last && python3 $X/stacgrid/r_to_npz.py /out/sg_r_stacit /out/sg_r_stacit.npz"
C=$X/ga-sar-ice/compare.py
step cmp_odc_py python3 $C /out/odc.npz /out/sg_py.npz
step cmp_odc_r python3 $C /out/odc.npz /out/sg_r.npz
step cmp_py_r python3 $C /out/sg_py.npz /out/sg_r.npz
step cmp_stacit_py_r python3 $C /out/sg_py_stacit.npz /out/sg_r_stacit.npz
rm -rf /out/sg_r /out/sg_r_stacit
