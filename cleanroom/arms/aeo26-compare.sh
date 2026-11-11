#!/usr/bin/env bash
# aeo26-workshop presenters scripts, rasterio original vs osgeo.gdal port, on Ubuntu's one
# libgdal (python3-rasterio and python3-gdal from apt). Needs the workshop repo mounted:
#   MOUNT=$HOME/Git/aeo26-workshop:/aeo26:ro bash cleanroom/run.sh aeo26-compare
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments/aeo26
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends python3-gdal python3-rasterio python3-matplotlib python3-numpy python3-pil'
step versions python3 -c 'from osgeo import gdal; import rasterio, numpy, matplotlib; print("gdal", gdal.__version__, "rasterio", rasterio.__version__, rasterio.__gdal_version__, "numpy", numpy.__version__, "matplotlib", matplotlib.__version__)'
for v in orig gdal; do
  mkdir -p /work/$v/presenters && cp -r /aeo26/data /work/$v/ && cp $X/$v/*.py /work/$v/presenters/
  step check_$v python3 /work/$v/presenters/check_values.py --out /out/check_values_$v.md
  step examples_$v python3 /work/$v/presenters/make_examples.py
  mkdir -p /out/examples_$v && cp /work/$v/examples/*.png /out/examples_$v/
done
step compare bash -c '
  diff /out/check_values_orig.md /out/check_values_gdal.md && echo "check_values: identical"
  diff <(grep -v "^wrote" /out/examples_orig.log) <(grep -v "^wrote" /out/examples_gdal.log) && echo "make_examples printed numbers: identical"
  for f in /out/examples_orig/*.png; do cmp -s "$f" /out/examples_gdal/$(basename $f) && echo "$(basename $f): byte-identical" || echo "$(basename $f): DIFFERS"; done
  python3 - <<PY
from PIL import Image, ImageChops
import glob, os
for f in sorted(glob.glob("/out/examples_orig/*.png")):
    a = Image.open(f).convert("RGB"); b = Image.open(f.replace("_orig", "_gdal")).convert("RGB")
    d = ImageChops.difference(a, b).getbbox()
    print(os.path.basename(f), a.size, b.size, "pixel diff bbox:", d)
PY'
cat /out/compare.log
