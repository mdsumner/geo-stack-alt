#!/usr/bin/env bash
# fast-ice NormCovar (fast_ice_from_stac_xarray.ipynb sections 3, 5-10: EW load, dB, pairs, NormCovar,
# RGB, resample, landmask; not SAM/SVM). Three pixi envs:
#   ref     the notebook's code + normalized_covariance d6843d2, at fast-ice 4694c6c's locked versions
#           of the packages on this path (pixi.lock: gdal 3.12.3, rasterio 1.5.0, odc-stac 0.5.2,
#           odc-geo 0.5.1, xarray 2026.4.0, numpy 2.5.0, pandas 3.0.3, rioxarray 0.22.0); no torch
#   mid     ref, but rasterio 1.5.2 / GDAL 3.13.3 (what fast-ice's ranges resolve to today; with
#           odc-stac kept at 0.5.2 so section 8 runs)
#   latest  the same, resolved today within fast-ice's declared ranges (odc-stac 0.5.3 ...)
#   alt     python numpy scipy gdal + R gdalraster ximage: stacgrid, nc_gdal.py, nc_r.R
#   MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh normcovar
set -uo pipefail
source /cleanroom/arms/lib.sh
export LANG=C.UTF-8 LC_ALL=C.UTF-8
N=/cleanroom/experiments/normcovar; SG=/stacgrid
NC="normalized-covariance @ git+https://github.com/jlo031/normalized_covariance@d6843d2a31b57bb7e42ca531aff5077ea4a56fe4"
COMMON="geopandas pystac-client botocore dask loguru pyyaml matplotlib-base pyarrow"
REF="python=3.13 gdal=3.12.3 libgdal-core=3.12.3 rasterio=1.5.0 odc-stac=0.5.2 odc-geo=0.5.1 xarray=2026.4.0 numpy=2.5.0 scipy=1.18.0 pandas=3.0.3 rioxarray=0.22.0 $COMMON"
MID="python=3.13 gdal=3.13.3 libgdal-core=3.13.3 rasterio=1.5.2 odc-stac=0.5.2 odc-geo=0.5.1 xarray=2026.4.0 numpy=2.5.0 scipy=1.18.0 pandas=3.0.3 rioxarray=0.22.0 $COMMON"
LATEST="python=3.13 gdal rasterio odc-stac odc-geo xarray numpy scipy pandas rioxarray<0.23 $COMMON"
ALT="python=3.13 numpy scipy gdal libgdal libgdal-arrow-parquet r-base r-gdalraster r-jsonlite r-curl"
printf 'ref: %s + pypi stac-geoparquet, %s\nmid: %s + same pypi\nlatest: %s + same pypi\nalt: %s + CRAN ximage\n' "$REF" "$NC" "$MID" "$LATEST" "$ALT" > /out/packages.txt
step apt bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends curl ca-certificates git'
step pixi_install bash -c 'curl -fsSL https://pixi.sh/install.sh | PIXI_NO_PATH_UPDATE=1 bash'
export PATH=$HOME/.pixi/bin:$PATH
mk() {  # mk <dir> <conda specs> [pypi...]
  local d=$1 spec=$2; shift 2
  mkdir -p $d && cd $d && pixi init . >/dev/null && pixi add $spec && { [ $# -eq 0 ] || pixi add --pypi "$@"; }; local rc=$?; cd /; return $rc
}
step env_ref mk /work/ref "$REF" "stac-geoparquet>=0.8,<0.9" "$NC"
step env_mid mk /work/mid "$MID" "stac-geoparquet>=0.8,<0.9" "$NC"
step env_latest mk /work/latest "$LATEST" "stac-geoparquet>=0.8,<0.9" "$NC"
step env_alt bash -c "$(declare -f mk); mk /work/alt '$ALT' && cd /work/alt && pixi run Rscript -e 'install.packages(\"ximage\", repos = \"https://cloud.r-project.org\"); stopifnot(requireNamespace(\"ximage\"))'"
R() { local e=$1; shift; pixi run --manifest-path /work/$e/pixi.toml "$@"; }
step versions bash -c "$(declare -f R); for e in ref mid latest alt; do echo \$e; R \$e python -c 'from osgeo import gdal; import numpy, scipy; print(\"gdal\", gdal.__version__, \"numpy\", numpy.__version__, \"scipy\", scipy.__version__)'; done
  for e in ref mid latest; do R \$e python -c 'import odc.stac, odc.geo, xarray, rasterio, pandas; print(\"odc-stac\", odc.stac.__version__, \"odc-geo\", odc.geo.__version__, \"xarray\", xarray.__version__, \"rasterio\", rasterio.__version__, rasterio.__gdal_version__, \"pandas\", pandas.__version__)'; done
  R alt Rscript -e 'cat(\"gdalraster\", format(packageVersion(\"gdalraster\")), \"ximage\", format(packageVersion(\"ximage\")), gdalraster::gdal_version()[1], \"\n\")'"
# the coastline for the ports (the reference script fetches its own, same URL, same check)
COAST="https://ramadda.data.bas.ac.uk/repository/entry/get/add_coastline_medium_res_polygon_v7_12.shp.zip?entryid=synth%3Ac9c6d671-ad19-4a78-96b2-7d47e9bac46a%3AL2FkZF9jb2FzdGxpbmVfbWVkaXVtX3Jlc19wb2x5Z29uX3Y3XzEyLnNocC56aXA%3D"
step coast bash -c "mkdir -p /work/coast && cd /work/coast && curl -fsSL -o c.zip '$COAST' && echo 'b0172d698436f871f49339cea5c7155e3d98648360521cc4bbc44a026c0edc38  c.zip' | sha256sum -c && R() { pixi run --manifest-path /work/alt/pixi.toml \"\$@\"; } && R python -c 'import zipfile; zipfile.ZipFile(\"c.zip\").extractall(\".\")'"
SHP=/work/coast/add_coastline_medium_res_polygon_v7_12.shp
step ref R ref python $N/nc_ref.py /out/ref.npz
step ref_mid R mid python $N/nc_ref.py /out/ref_mid.npz
step ref_latest R latest python $N/nc_ref.py /out/ref_latest.npz
step py R alt python $N/nc_gdal.py $SG $SHP /out/py.npz
step py_odc env NC_ODC_NODATA=1 pixi run --manifest-path /work/alt/pixi.toml python $N/nc_gdal.py $SG $SHP /out/py_odc.npz
step r bash -c "$(declare -f R); R alt Rscript $N/nc_r.R $SG $SHP /out/r && R alt python $N/r_to_npz.py /out/r /out/r.npz"
step r_odc bash -c "$(declare -f R); NC_ODC_NODATA=1 R alt Rscript $N/nc_r.R $SG $SHP /out/r_odc && R alt python $N/r_to_npz.py /out/r_odc /out/r_odc.npz"
step cmp_ref_py R alt python $N/compare.py /out/ref.npz /out/py.npz
step cmp_ref_r R alt python $N/compare.py /out/ref.npz /out/r.npz
step cmp_mid_py R alt python $N/compare.py /out/ref_mid.npz /out/py.npz
step cmp_mid_py_odc R alt python $N/compare.py /out/ref_mid.npz /out/py_odc.npz
step cmp_mid_r_odc R alt python $N/compare.py /out/ref_mid.npz /out/r_odc.npz
step cmp_py_r R alt python $N/compare.py /out/py.npz /out/r.npz
for e in ref mid latest; do step rio_checks_$e R $e python $N/rio_checks.py; done
step gdal_checks_ref R ref python $N/gdal_checks.py $SHP
step gdal_checks_alt R alt python $N/gdal_checks.py $SHP
step summary R alt python - <<'PY'
import glob, json, os
for f in sorted(glob.glob("/out/cmp_*.log")):
    t = open(f).read(); r = json.loads(t[t.index("{"):])
    print(os.path.basename(f)[4:-4], {k: v["n_differ"] for k, v in r.items() if isinstance(v, dict) and "n_differ" in v},
          "pairs", r["n_pairs"], "same_gt", r["same_gt"], r["same_gt_resampled"])
PY
mv /out/r/normcovar_r.png /out/normcovar_r.png; mv /out/r_odc/normcovar_r.png /out/normcovar_r_odc_nodata.png
rm -rf /out/r /out/r_odc /out/*.npz
for e in ref mid latest alt; do cp /work/$e/pixi.toml /out/pixi-$e.toml; cp /work/$e/pixi.lock /out/pixi-$e.lock; done 2>/dev/null
