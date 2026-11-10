#!/usr/bin/env bash
# The alt stack end to end on Ubuntu apt: osgeo.gdal port for the alignment, then the figure
# step twice, matplotlib (Python) and ximage + gdalraster (R via r2u), on one distro libgdal.
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments/tas-s1
EVERY=${EVERY:-40}
OPTS="--level 1 --boxcar 3 --res 100 --threads 8"
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates python3-gdal python3-matplotlib python3-numpy'
step r2u_setup bash -c "curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash"
step r_install Rscript -e 'install.packages(c("gdalraster", "ximage", "jsonlite")); cat("gdalraster", format(packageVersion("gdalraster")), "ximage", format(packageVersion("ximage")), gdalraster::gdal_version()[1], "\n")'
export TAS_S1_WORK=/out/work TAS_S1_OUT=/out/out
mkdir -p $TAS_S1_WORK $TAS_S1_OUT
# the S3 listing is flaky from containers; reuse the index from the tas-s1-compare run
cp $X/index.json /out/work/index.json
BURSTS=$(python3 -c "import json; ix=json.load(open('/out/work/index.json')); print(' '.join(e['burst'] for e in ix[::$EVERY]))")
echo "$BURSTS" > /out/bursts.txt
step burst python3 $X/tas_s1_change_gdal.py burst $OPTS --burst $BURSTS
step mosaic python3 $X/tas_s1_change_gdal.py mosaic $OPTS --by-orbit
step figure_py python3 $X/tas_s1_change_gdal.py figure $OPTS
step figure_r Rscript $X/figure.R /out/out/tas_s1_change_all_100m.tif /out/out 4000
step stats_compare python3 -c '
import json
p = json.load(open("/out/out/tas_s1_change_stats_100m.json")); r = json.load(open("/out/out/tas_s1_change_stats_100m_r.json"))
for b in p:
    print(b, {k: (p[b][k], r[b][k], abs(p[b][k] - r[b][k])) for k in p[b]})'
rm -f /out/work/ne_10m_*.geojson
