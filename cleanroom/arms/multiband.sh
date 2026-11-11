#!/usr/bin/env bash
# multi-band assets: Earth Search sentinel-2-l2a "visual" (3-band TCI) west of Hobart, Dec 2021 - Feb 2022,
# across the 55GDN/55GEN tile overlap. odc-stac (as is, and with raster:bands added) vs stacgrid
# Python and R ("visual.1".."visual.3", "visual", "red"). One pixi env.
#   MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh multiband
set -uo pipefail
source /cleanroom/arms/lib.sh
export LANG=C.UTF-8 LC_ALL=C.UTF-8
S=/cleanroom/experiments/multiband; SG=/stacgrid
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
mkdir -p /work/geo && cd /work/geo
step pixi_init pixi init .
step add pixi add python numpy gdal libgdal r-base r-gdalraster r-jsonlite r-curl odc-stac pystac-client botocore dask
eval "$(pixi shell-hook)"
cd /
step versions bash -c 'python -c "from osgeo import gdal; import odc.stac; print(\"gdal\", gdal.__version__, \"odc-stac\", odc.stac.__version__)"'
step odc python $S/odc_visual.py /out/ref.npz
step sg_py python $S/sg_visual.py $SG /out/sg_py.npz
step sg_r bash -c "Rscript $S/sg_visual.R $SG /out/r && python $S/r_to_npz.py /out/r /out/sg_r.npz"
step cmp_py python $S/compare.py /out/ref.npz /out/sg_py.npz
step cmp_r python $S/compare.py /out/ref.npz /out/sg_r.npz
rm -rf /out/r /out/*.npz
cp /work/geo/pixi.toml /work/geo/pixi.lock /out/ 2>/dev/null
