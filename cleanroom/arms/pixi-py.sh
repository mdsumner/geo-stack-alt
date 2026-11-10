#!/usr/bin/env bash
# Arm B-py: pixi, Python only. Packages from PIXI_PKGS (default: the stance's Python half).
# If rasterio is in the env, also runs the rasterio probe, to see whether conda-forge's
# rasterio/pyogrio share the env's one libgdal.
set -uo pipefail
source /cleanroom/arms/lib.sh
PKGS=${PIXI_PKGS:-python numpy gdal libgdal matplotlib-base}
echo "$PKGS" > /out/packages.txt

step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
mkdir -p /work/geo && cd /work/geo
step pixi_init pixi init .
step add pixi add $PKGS
step probe_py pixi run python /cleanroom/probe/probe_gdal.py /out/probe_py.json
if pixi run python -c "import sys; from osgeo import ogr; sys.exit(ogr.GetDriverByName('Parquet') is None)"; then
  step probe_parquet pixi run python /cleanroom/probe/probe_parquet.py /out/probe_parquet.json
fi
if pixi list | grep -q '^rasterio '; then
  step probe_rasterio pixi run python /cleanroom/probe/probe_rasterio.py /out/probe_rasterio.json
fi
step sizes bash -c 'echo "env_bytes $(du -sb /work/geo/.pixi/envs/default | cut -f1)"; echo "env_files $(find /work/geo/.pixi/envs/default -type f | wc -l)"; echo "cache_bytes $(du -sb $HOME/.cache/rattler | cut -f1)"; echo "disk_total_bytes $(du -sbc /work/geo/.pixi/envs/default $HOME/.cache/rattler | tail -1 | cut -f1)  (env + cache, hardlinks counted once)"; pixi --version; pixi list > /out/pixi-list.txt'
cp pixi.toml pixi.lock /out/ 2>/dev/null
cat /out/sizes.log
