#!/usr/bin/env bash
# The four project ports on pixi: one conda-forge env, one libgdal, shared by osgeo.gdal,
# rasterio, odc-stac and R. Same steps as the apt arms (tas-s1-compare/-figure, aeo26-compare/
# -figure, ga-sar-ice-compare, stacgrid), so each original-vs-port comparison is again on one
# libgdal, and the outputs can be set against the apt (GDAL 3.8.4) runs afterwards.
#   MOUNT="$HOME/Git/aeo26-workshop:/aeo26:ro $PWD/stacgrid:/stacgrid:ro" bash cleanroom/run.sh pixi-projects
# The alt stack proper is the "stack" add; "baseline" adds only what the originals need.
set -uo pipefail
source /cleanroom/arms/lib.sh
export LANG=C.UTF-8 LC_ALL=C.UTF-8
X=/cleanroom/experiments
STACK="python numpy gdal libgdal matplotlib-base pillow r-base r-gdalraster r-jsonlite"
BASELINE="rasterio shapely odc-stac pystac-client botocore"
echo "stack: $STACK" > /out/packages.txt; echo "baseline: $BASELINE" >> /out/packages.txt

step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
mkdir -p /work/geo && cd /work/geo
step pixi_init pixi init .
step add_stack pixi add $STACK
# ximage: pure R, not on conda-forge yet (r-ximage submitted); CRAN source, no compiler
step ximage pixi run Rscript -e 'install.packages("ximage", repos = "https://cloud.r-project.org"); stopifnot(requireNamespace("ximage"))'
step add_baseline pixi add $BASELINE
eval "$(pixi shell-hook)"
cd /
step versions bash -c 'python -c "from osgeo import gdal; import rasterio, numpy, odc.stac; print(\"gdal\", gdal.__version__, \"rasterio\", rasterio.__version__, rasterio.__gdal_version__, \"numpy\", numpy.__version__, \"odc-stac\", odc.stac.__version__)"; Rscript -e "cat(\"gdalraster\", format(packageVersion(\"gdalraster\")), \"ximage\", format(packageVersion(\"ximage\")), gdalraster::gdal_version()[1], \"\n\")"'

## tasmania-s1-change: original vs port, then R figure from the port's mosaic
T=$X/tas-s1; EVERY=${EVERY:-40}; OPTS="--level 1 --boxcar 3 --res 100 --threads 8"
mkdir -p /out/tas/rio/work /out/tas/gdal/work
cp $T/index.json /out/tas/rio/work/; cp $T/index.json /out/tas/gdal/work/
BURSTS=$(python -c "import json; ix=json.load(open('$T/index.json')); print(' '.join(e['burst'] for e in ix[::$EVERY]))")
echo "$BURSTS" > /out/tas/bursts.txt
for v in rio gdal; do
  s=$T/tas_s1_change.py; [ $v = gdal ] && s=$T/tas_s1_change_gdal.py
  e="env TAS_S1_WORK=/out/tas/$v/work TAS_S1_OUT=/out/tas/$v/out"
  step tas_burst_$v $e python $s burst $OPTS --burst $BURSTS
  [ $v = gdal ] && cp /out/tas/rio/work/ne_10m_*.geojson /out/tas/gdal/work/ 2>/dev/null
  step tas_mosaic_$v $e python $s mosaic $OPTS --by-orbit
  step tas_figure_$v $e python $s figure $OPTS
done
step tas_compare python $T/compare.py /out/tas/rio/work /out/tas/rio/out /out/tas/gdal/work /out/tas/gdal/out /out/tas/compare.json
step tas_figure_r Rscript $T/figure.R /out/tas/gdal/out/tas_s1_change_all_100m.tif /out/tas/gdal/out 4000
step tas_stats_compare python -c '
import json
p = json.load(open("/out/tas/gdal/out/tas_s1_change_stats_100m.json")); r = json.load(open("/out/tas/gdal/out/tas_s1_change_stats_100m_r.json"))
for b in p:
    print(b, {k: (p[b][k], r[b][k], abs(p[b][k] - r[b][k])) for k in p[b]})'
rm -f /out/tas/*/work/ne_10m_*.geojson

## aeo26-workshop presenters: original vs port, then R figures
A=$X/aeo26; mkdir -p /out/aeo26
for v in orig gdal; do
  mkdir -p /work/aeo26/$v/presenters && cp -r /aeo26/data /work/aeo26/$v/ && cp $A/$v/*.py /work/aeo26/$v/presenters/
  step aeo_check_$v python /work/aeo26/$v/presenters/check_values.py --out /out/aeo26/check_values_$v.md
  step aeo_examples_$v python /work/aeo26/$v/presenters/make_examples.py
  mkdir -p /out/aeo26/examples_$v && cp /work/aeo26/$v/examples/*.png /out/aeo26/examples_$v/
done
step aeo_compare bash -c '
  diff /out/aeo26/check_values_orig.md /out/aeo26/check_values_gdal.md && echo "check_values: identical"
  diff <(grep -v "^wrote" /out/aeo_examples_orig.log) <(grep -v "^wrote" /out/aeo_examples_gdal.log) && echo "make_examples printed numbers: identical"
  for f in /out/aeo26/examples_orig/*.png; do cmp -s "$f" /out/aeo26/examples_gdal/$(basename $f) && echo "$(basename $f): byte-identical" || echo "$(basename $f): DIFFERS"; done'
step aeo_examples_r Rscript $A/r/make_examples.R /work/aeo26/gdal /out/aeo26/r
step aeo_printed bash -c 'diff <(grep -v "^wrote" /out/aeo_examples_gdal.log) <(grep -v -e "^wrote" -e codetools /out/aeo_examples_r.log) && echo "printed numbers: identical"'
step aeo_fesm_pixels python -c '
import numpy as np
from osgeo import gdal
ds = gdal.Open("/work/aeo26/gdal/data/fire_severity_2019_20.tif")
py = ds.ReadAsArray()[::2, ::2].astype("int32")
r = np.fromfile("/out/aeo26/r/fesm_decimated.int32", "int32").reshape(py.shape)
print("decimated severity, Python vs R: shape", py.shape, "differ:", int((py != r).sum()))'
rm -f /out/aeo26/r/fesm_decimated.int32

## ga-sar-ice: odc-stac vs plain GDAL vs STACIT vs stacgrid (Python and R)
G=$X/ga-sar-ice; C=$G/compare.py; mkdir -p /out/ga
step ga_odc python $G/odc_load.py /out/ga/odc.npz
step ga_gdal python $G/gdal_load.py /out/ga/gdal.npz
step ga_stacit python $G/stacit_load.py /out/ga/stacit.npz
step ga_gdal_noovr_last env GDAL_LOAD_OVR=NONE GDAL_LOAD_FUSE=last python $G/gdal_load.py /out/ga/gdal_noovr_last.npz
step ga_sg_py python $X/stacgrid/ga_py.py /stacgrid /out/ga/sg_py.npz
step ga_sg_r bash -c "Rscript $X/stacgrid/ga_r.R /stacgrid /out/ga/sg_r && python $X/stacgrid/r_to_npz.py /out/ga/sg_r /out/ga/sg_r.npz"
step ga_cmp_odc_gdal python $C /out/ga/odc.npz /out/ga/gdal.npz
step ga_cmp_stacit python $C /out/ga/gdal_noovr_last.npz /out/ga/stacit.npz
step ga_cmp_odc_sg_py python $C /out/ga/odc.npz /out/ga/sg_py.npz
step ga_cmp_odc_sg_r python $C /out/ga/odc.npz /out/ga/sg_r.npz
rm -rf /out/ga/sg_r

step sizes bash -c 'echo "env_bytes $(du -sb /work/geo/.pixi/envs/default | cut -f1)"; pixi --version; pixi list --manifest-path /work/geo/pixi.toml > /out/pixi-list.txt'
cp /work/geo/pixi.toml /work/geo/pixi.lock /out/ 2>/dev/null
