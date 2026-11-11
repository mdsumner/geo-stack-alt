#!/usr/bin/env bash
# Same port, two installs: the apt runs (Ubuntu libgdal 3.8.4) against a pixi-projects run
# (conda-forge libgdal). Reads only; the comparison tools come from apt.
#   MOUNT="$PWD/evidence:/ev:ro" PIXI_RUN=pixi-projects/ubuntu-24.04_<stamp> bash cleanroom/run.sh cross-stack
set -uo pipefail
source /cleanroom/arms/lib.sh
export DEBIAN_FRONTEND=noninteractive
X=/cleanroom/experiments
P=/ev/${PIXI_RUN:?}
TAS=/ev/${APT_TAS:-tas-s1-figure/ubuntu-24.04_20261110T230412Z}
AEO=/ev/${APT_AEO:-aeo26-compare/ubuntu-24.04_20261110T235849Z}
AEOR=/ev/${APT_AEOR:-aeo26-figure/ubuntu-24.04_20261111T031303Z}
GA=/ev/${APT_GA:-ga-sar-ice-compare/ubuntu-24.04_20261111T003153Z}
# STACIT needs GDAL >= 3.10 for DEA's proj:code items, so its apt reference is the 26.04 run
GAS=/ev/${APT_GA_STACIT:-ga-sar-ice-compare/ubuntu-26.04_20261111T003755Z}
SG=/ev/${APT_SG:-stacgrid/ubuntu-24.04_20261111T014224Z}
printf 'pixi %s\ntas %s\naeo %s\naeo_r %s\nga %s\nga_stacit %s\nstacgrid %s\n' $P $TAS $AEO $AEOR $GA $GAS $SG > /out/inputs.txt
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends python3-gdal python3-numpy python3-pil'
# tasmania: the port's bursts and mosaics, apt vs pixi
step tas python3 $X/tas-s1/compare.py $TAS/work $TAS/out $P/tas/gdal/work $P/tas/gdal/out /out/tas.json
step aeo bash -c "
  diff $AEO/check_values_gdal.md $P/aeo26/check_values_gdal.md && echo 'check_values: identical'
  diff <(grep -v '^wrote' $AEO/examples_gdal.log) <(grep -v '^wrote' $P/aeo_examples_gdal.log) && echo 'make_examples printed numbers: identical'
  diff <(grep -v -e '^wrote' -e codetools $AEOR/examples_r.log) <(grep -v -e '^wrote' -e codetools $P/aeo_examples_r.log) && echo 'R printed numbers: identical'
  python3 - <<PY
from PIL import Image, ImageChops
import glob, os
for sub in ['examples_gdal', 'r']:
    base = '$AEO' if sub == 'examples_gdal' else '$AEOR'
    for f in sorted(glob.glob(f'{base}/{sub}/*.png')):
        g = f'$P/aeo26/{sub}/' + os.path.basename(f)
        a = Image.open(f).convert('RGB'); b = Image.open(g).convert('RGB')
        d = ImageChops.difference(a, b)
        n = sum(1 for p in d.getdata() if p != (0, 0, 0)) if a.size == b.size else None
        print(sub, os.path.basename(f), a.size, b.size, 'pixels differing:', n, 'bbox:', d.getbbox() if n else None)
PY"
C=$X/ga-sar-ice/compare.py
step ga_odc python3 $C $GA/odc.npz $P/ga/odc.npz
step ga_gdal python3 $C $GA/gdal.npz $P/ga/gdal.npz
step ga_stacit python3 $C $GAS/stacit.npz $P/ga/stacit.npz
step ga_sg_py python3 $C $SG/sg_py.npz $P/ga/sg_py.npz
step ga_sg_r python3 $C $SG/sg_r.npz $P/ga/sg_r.npz
