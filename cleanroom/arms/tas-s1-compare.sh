#!/usr/bin/env bash
# tasmania-s1-change, rasterio original vs osgeo.gdal port, on one libgdal: Ubuntu's.
# python3-rasterio and python3-gdal both link the distro libgdal, so any difference in the
# outputs comes from the code paths, not from two GDAL builds. A subset of bursts at the
# README's quicklook settings (level 1 = 80 m inputs, boxcar 3, 100 m mosaic).
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments/tas-s1
EVERY=${EVERY:-40}
OPTS="--level 1 --boxcar 3 --res 100 --threads 8"
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends ca-certificates python3-gdal python3-rasterio python3-shapely python3-matplotlib python3-numpy'
step versions python3 -c 'from osgeo import gdal; import rasterio, numpy; print("gdal", gdal.__version__, "rasterio", rasterio.__version__, "rasterio_gdal", rasterio.__gdal_version__, "numpy", numpy.__version__)'
mkdir -p /out/rio/work /out/gdal/work
step index env TAS_S1_WORK=/out/rio/work python3 $X/tas_s1_change.py index --threads 16
cp /out/rio/work/index.json /out/gdal/work/
BURSTS=$(python3 -c "import json; ix=json.load(open('/out/rio/work/index.json')); print(' '.join(e['burst'] for e in ix[::$EVERY]))")
echo "$BURSTS" > /out/bursts.txt
for v in rio gdal; do
  s=$X/tas_s1_change.py; [ $v = gdal ] && s=$X/tas_s1_change_gdal.py
  e="env TAS_S1_WORK=/out/$v/work TAS_S1_OUT=/out/$v/out"
  step burst_$v $e python3 $s burst $OPTS --burst $BURSTS
  # share the Natural Earth download so both land masks start from the same bytes
  [ $v = gdal ] && cp /out/rio/work/ne_10m_*.geojson /out/gdal/work/ 2>/dev/null
  step mosaic_$v $e python3 $s mosaic $OPTS --by-orbit
  step figure_$v $e python3 $s figure $OPTS
done
step compare python3 $X/compare.py /out/rio/work /out/rio/out /out/gdal/work /out/gdal/out /out/compare.json
cat /out/compare.log
rm -f /out/*/work/ne_10m_*.geojson
