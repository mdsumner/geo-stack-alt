#!/usr/bin/env bash
# Arm B: pixi on a bare image. One conda-forge environment holding GDAL, osgeo.gdal and R
# (gdalraster, vapour, wk), plus ximage from CRAN. Then the same probes as every arm.
set -uo pipefail
source /cleanroom/arms/lib.sh

# A bare ubuntu image has neither curl nor CA certificates; a desktop install has both.
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'

step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH

mkdir -p /work/geo && cd /work/geo
step pixi_init pixi init .
# Python side first, then R, so the cost of each half is visible.
step add_python pixi add python numpy gdal ${PIXI_EXTRA:-}
step add_r pixi add r-base r-gdalraster r-vapour r-wk r-jsonlite
# ximage is pure R and not on conda-forge yet: CRAN source install, no compiler needed.
# (Not captured by pixi.lock: see notes in README.)
step ximage pixi run Rscript -e 'install.packages("ximage", repos = "https://cloud.r-project.org"); stopifnot(requireNamespace("ximage"))'

step probe_py pixi run python /cleanroom/probe/probe_gdal.py /out/probe_py.json
step probe_r pixi run Rscript /cleanroom/probe/probe.R /out/probe_r.json /out/dem_r.png

step sizes bash -c 'du -sh /work/geo/.pixi/envs/default $HOME/.cache/rattler 2>/dev/null; pixi --version; pixi list > /out/pixi-list.txt'
cp pixi.toml pixi.lock /out/ 2>/dev/null
cat /out/sizes.log
