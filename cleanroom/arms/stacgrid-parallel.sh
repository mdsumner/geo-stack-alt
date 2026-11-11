#!/usr/bin/env bash
# stacgrid parallel reads: the GA tutorial load at 1, 4, 8 and 16 workers, Python (threads) and
# R (forked processes), each checked against odc.stac.load in every pixel. One libgdal (apt).
#   MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh stacgrid-parallel
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments
SG=/stacgrid
C=$X/ga-sar-ice/compare.py
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates python3-gdal python3-numpy python3-rasterio python3-venv python3-pip'
export NPV=$(python3 -c "import numpy; print(numpy.__version__)")
step venv bash -c 'python3 -m venv --system-site-packages /venv && /venv/bin/pip install -q "numpy==$NPV" "odc-stac[botocore]>=0.5.2,<0.6" "pystac-client>=0.9,<0.10"'
step r2u_setup bash -c "curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash"
step r_install Rscript -e 'install.packages(c("gdalraster", "jsonlite")); cat("gdalraster", format(packageVersion("gdalraster")), gdalraster::gdal_version()[1], "\n")'
step odc /venv/bin/python $X/ga-sar-ice/odc_load.py /out/odc.npz
for w in 1 4 8 16; do
  step py_w$w env STACGRID_WORKERS=$w python3 $X/stacgrid/ga_py.py $SG /out/py_w$w.npz
  step r_w$w bash -c "STACGRID_WORKERS=$w Rscript $X/stacgrid/ga_r.R $SG /out/r_w$w && python3 $X/stacgrid/r_to_npz.py /out/r_w$w /out/r_w$w.npz"
done
# second pass, reversed order, to see how much of the timing is the network
for w in 16 8 4 1; do
  step py_w${w}_again env STACGRID_WORKERS=$w python3 $X/stacgrid/ga_py.py $SG /out/py_w${w}_again.npz
  step r_w${w}_again bash -c "STACGRID_WORKERS=$w Rscript $X/stacgrid/ga_r.R $SG /out/r_w${w}_again && python3 $X/stacgrid/r_to_npz.py /out/r_w${w}_again /out/r_w${w}_again.npz"
done
step compare bash -c "for f in /out/py_w*.npz /out/r_w*.npz; do python3 $C /out/odc.npz \$f | python3 -c \"import json,sys; r=json.load(sys.stdin); print('\$(basename \$f)', 'vs odc: same items', r['same_items'], 'hh differ', r['hh']['n_differ'], 'finite disagree', r['hh']['finite_disagree'], 'mask differ', r['mask']['n_differ'])\"; done"
step timings bash -c 'grep -h "items," /out/py_w*.log /out/r_w*.log /dev/null; for f in /out/py_w*.log /out/r_w*.log; do echo "$(basename $f .log) $(tail -1 $f)"; done'
rm -rf /out/r_w*/ /out/py_w*.npz /out/r_w*.npz
