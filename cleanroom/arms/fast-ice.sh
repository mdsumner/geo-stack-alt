#!/usr/bin/env bash
# fast-ice notebooks (abradley60/fast-ice 4694c6c): the STAC loads of sentinel_1_load_demo and
# fast_ice_from_stac_xarray, odc-stac (the notebooks' calls) vs stacgrid in Python and R, one
# pixi env, one libgdal. The EW route reads STAC-GeoParquet, so GDAL needs libgdal-arrow-parquet.
# Python 3.13 because fast-ice pins <3.14 and its stac-geoparquet 0.8 comes from PyPI.
# Also re-checks stacgrid on the GA tutorial load (solar-day rule changed for fast-ice).
#   MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh fast-ice
set -uo pipefail
source /cleanroom/arms/lib.sh
export LANG=C.UTF-8 LC_ALL=C.UTF-8
X=/cleanroom/experiments; F=$X/fast-ice; SG=/stacgrid
STACK="python=3.13 numpy gdal libgdal libgdal-arrow-parquet r-base r-gdalraster r-jsonlite r-curl"
BASELINE="odc-stac pystac-client geopandas rioxarray pyarrow botocore dask"
printf 'stack: %s\nbaseline: %s + pypi stac-geoparquet>=0.8,<0.9\n' "$STACK" "$BASELINE" > /out/packages.txt
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
mkdir -p /work/geo && cd /work/geo
step pixi_init pixi init .
step add_stack pixi add $STACK
step add_baseline bash -c "pixi add $BASELINE && pixi add --pypi 'stac-geoparquet>=0.8,<0.9'"
eval "$(pixi shell-hook)"
cd /
step versions bash -c 'python -c "from osgeo import gdal; import odc.stac, stac_geoparquet, pandas, geopandas; print(\"gdal\", gdal.__version__, \"odc-stac\", odc.stac.__version__, \"stac-geoparquet\", stac_geoparquet.__version__, \"pandas\", pandas.__version__, \"geopandas\", geopandas.__version__)"; Rscript -e "cat(\"gdalraster\", format(packageVersion(\"gdalraster\")), gdalraster::gdal_version()[1], \"\n\")"'
step odc_demo python $F/odc_demo.py /out/odc_demo.npz
step odc_xarray python $F/odc_xarray.py /out/odc_xarray.npz
step sg_py_demo python $F/sg_demo.py $SG /out/sg_py_demo.npz
step sg_py_xarray python $F/sg_xarray.py $SG /out/sg_py_xarray.npz
step sg_r_demo bash -c "Rscript $F/sg_demo.R $SG /out/r_demo && python $F/r_to_npz.py /out/r_demo /out/sg_r_demo.npz api pq"
step sg_r_xarray bash -c "Rscript $F/sg_xarray.R $SG /out/r_xarray && python $F/r_to_npz.py /out/r_xarray /out/sg_r_xarray.npz ew iw"
step cmp_demo_py python $F/compare.py /out/odc_demo.npz /out/sg_py_demo.npz api pq
step cmp_demo_r python $F/compare.py /out/odc_demo.npz /out/sg_r_demo.npz api pq
step cmp_xarray_py python $F/compare.py /out/odc_xarray.npz /out/sg_py_xarray.npz ew iw
step cmp_xarray_r python $F/compare.py /out/odc_xarray.npz /out/sg_r_xarray.npz ew iw
# the GA tutorial load again, with group_items(..., grid=) (odc's solar-day rule)
step ga_odc python $X/ga-sar-ice/odc_load.py /out/ga_odc.npz
step ga_sg_py python $X/stacgrid/ga_py.py $SG /out/ga_sg_py.npz
step ga_sg_r bash -c "Rscript $X/stacgrid/ga_r.R $SG /out/ga_r && python $X/stacgrid/r_to_npz.py /out/ga_r /out/ga_sg_r.npz"
step ga_cmp_py python $X/ga-sar-ice/compare.py /out/ga_odc.npz /out/ga_sg_py.npz
step ga_cmp_r python $X/ga-sar-ice/compare.py /out/ga_odc.npz /out/ga_sg_r.npz
step summary bash -c 'for f in /out/cmp_*.log; do python -c "
import json, sys; r = json.load(open(sys.argv[1]))
for k, v in r.items(): print(sys.argv[2], k, \"items\", v[\"n_items\"], \"same\", v[\"same_items\"], \"shape\", v[\"shape\"][0], \"same_gt\", v[\"same_gt\"], \"differ\", v.get(\"n_differ\"), \"finite_disagree\", v.get(\"finite_disagree\"), \"of\", v.get(\"of\"))
" $f $(basename $f .log); done; for f in /out/ga_cmp_*.log; do python -c "
import json, sys; r = json.load(open(sys.argv[1])); print(sys.argv[2], \"items\", r[\"n_items\"], \"hh differ\", r[\"hh\"][\"n_differ\"], \"mask differ\", r[\"mask\"][\"n_differ\"])
" $f $(basename $f .log); done'
rm -rf /out/r_demo /out/r_xarray /out/ga_r /out/*.npz
cp /work/geo/pixi.toml /work/geo/pixi.lock /out/ 2>/dev/null
