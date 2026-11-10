#!/usr/bin/env bash
# Experiment: explicit XSCALE/YSCALE under GDAL 3.12 and 3.13 (computed XSCALE/YSCALE).
set -uo pipefail
source /cleanroom/arms/lib.sh
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
for v in 3.12 3.13; do
  mkdir -p /work/g$v && cd /work/g$v && pixi init . >/dev/null 2>&1
  step add_$v pixi add python numpy "gdal=$v"
  step scales_$v pixi run python /cleanroom/experiments/warp_scales.py /out $v
done
