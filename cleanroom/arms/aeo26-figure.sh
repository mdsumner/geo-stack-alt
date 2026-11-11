#!/usr/bin/env bash
# aeo26-workshop example figures, matplotlib (osgeo.gdal port) and R (ximage + gdalraster),
# all from apt and r2u on one libgdal. Needs the workshop repo mounted:
#   MOUNT=$HOME/Git/aeo26-workshop:/aeo26:ro bash cleanroom/run.sh aeo26-figure
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
# without a UTF-8 locale R's png device draws non-ASCII (the ·, –, → in titles) as ".."
export LANG=C.UTF-8 LC_ALL=C.UTF-8
X=/cleanroom/experiments/aeo26
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates python3-gdal python3-matplotlib python3-numpy python3-pil'
step r2u_setup bash -c "curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash"
step r_install Rscript -e 'install.packages(c("gdalraster", "ximage")); cat("gdalraster", format(packageVersion("gdalraster")), "ximage", format(packageVersion("ximage")), gdalraster::gdal_version()[1], "\n")'
mkdir -p /work/presenters && cp -r /aeo26/data /work/ && cp $X/gdal/*.py /work/presenters/
step examples_py python3 /work/presenters/make_examples.py
mkdir -p /out/py && cp /work/examples/*.png /out/py/
step examples_r Rscript $X/r/make_examples.R /work /out/r
step printed bash -c 'diff <(grep -v "^wrote" /out/examples_py.log) <(grep -v -e "^wrote" -e codetools /out/examples_r.log) && echo "printed numbers: identical"'
step fesm_pixels python3 -c '
import numpy as np
from osgeo import gdal
py = gdal.Open("/work/data/fire_severity_2019_20.tif").ReadAsArray()[::2, ::2].astype("int32")
r = np.fromfile("/out/r/fesm_decimated.int32", "int32").reshape(py.shape)
print("decimated severity, Python vs R: shape", py.shape, "differ:", int((py != r).sum()))'
rm -f /out/r/fesm_decimated.int32
