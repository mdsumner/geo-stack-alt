#!/usr/bin/env bash
# Experiment: same gdal.Warp across GDAL versions from conda-forge, outputs kept for diffing.
set -uo pipefail
source /cleanroom/arms/lib.sh
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
for v in ${GDAL_VERSIONS:-3.10 3.11 3.12 3.13}; do
  mkdir -p /work/g$v && cd /work/g$v && pixi init . >/dev/null 2>&1
  step add_$v pixi add python numpy "gdal=$v"
  step warp_$v pixi run python /cleanroom/experiments/warp_one.py /out/warp_$v.tif
done
