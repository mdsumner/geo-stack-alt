#!/usr/bin/env bash
# Prebuilt images from hypertidy/gdal-r-ci, used as they are (only ximage and the notebook's extra
# packages are added, the way the gdal-r-ci README says to add packages):
#   gdal-r-python  GDAL/PROJ/GEOS built from source into /usr/local; R and a uv venv (/opt/gdal-py)
#                  linked to them; rasterio/pyogrio/fiona/shapely/pyproj built from source
#     IMAGE=ghcr.io/hypertidy/gdal-r-python:latest MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh gdal-r-ci
#   gdal-conda     the conda-forge counterpart: one pixi env (libgdal + plugins, R and Python binaries)
#     IMAGE=ghcr.io/hypertidy/gdal-conda:latest MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh gdal-conda
# Steps:
#   probes     the same DEM probe as every arm: osgeo.gdal, rasterio, R (gdalraster, vapour), terra
#   census     one process per language loading everything GDAL-linked: which libgdal/libproj/libgeos files
#   stacgrid   the GA tutorial load: odc-stac (added with uv) vs stacgrid Python and R
#   normcovar  the fast-ice NormCovar ports (Python, R), and the notebook itself with its extra packages
#              added with uv into the image's venv, first as resolved today (odc-stac 0.5.3), then
#              with odc-stac 0.5.2
set -uo pipefail
source /cleanroom/arms/lib.sh
export LANG=C.UTF-8 LC_ALL=C.UTF-8
PY=$(command -v python)
if command -v uv >/dev/null; then UV="uv pip install --python $PY"; NBX=""; else UV="$PY -m pip install -q"; NBX="--ignore-requires-python"; fi
# NBX: normalized_covariance declares requires-python <3.14 and both images have 3.14; pip refuses it
# without --ignore-requires-python, uv installs it without comment
# odc-stac's loader fails under dask's array query planning (gdal-r-python sets it on); the odc steps
# run as the image is, and again with it off
OFF="env DASK_ARRAY__QUERY_PLANNING=False"
echo "python=$PY install='$UV' DASK_ARRAY__QUERY_PLANNING=${DASK_ARRAY__QUERY_PLANNING:-unset}" > /out/env.txt
X=/cleanroom/experiments; N=$X/normcovar; SG=/stacgrid
P=/cleanroom/probe

step versions bash -c "gdalinfo --version; $PY -c 'import sys; from osgeo import gdal; import numpy, scipy, rasterio, pyogrio, xarray, pandas, dask; print(sys.version.split()[0], \"gdal\", gdal.__version__, \"numpy\", numpy.__version__, \"scipy\", scipy.__version__, \"rasterio\", rasterio.__version__, rasterio.__gdal_version__, \"pyogrio\", pyogrio.__version__, pyogrio.__gdal_version_string__, \"xarray\", xarray.__version__, \"pandas\", pandas.__version__, \"dask\", dask.__version__)'; Rscript -e 'cat(R.version.string, \"\n\"); for (p in c(\"gdalraster\", \"vapour\", \"wk\", \"sf\", \"terra\", \"reticulate\")) cat(p, format(packageVersion(p)), \"\n\")'; du -sh /usr/local /opt/gdal-py /opt/gdal-conda 2>/dev/null; true"
step ximage Rscript -e 'install.packages("ximage", repos = "https://cloud.r-project.org"); stopifnot(requireNamespace("ximage"))'

# ---- probes (as every arm) ----
step probe_py $PY $P/probe_gdal.py /out/probe_py.json
step probe_rasterio $PY $P/probe_rasterio.py /out/probe_rasterio.json
step probe_r Rscript $P/probe.R /out/probe_r.json /out/dem_r.png
step probe_terra Rscript $P/probe_terra.R /out/probe_terra.json

# ---- census: one process per language, everything GDAL-linked loaded ----
step census_py $PY - <<'EOF'
import json
from osgeo import gdal, ogr, osr  # noqa: F401
import rasterio, pyogrio, shapely, pyproj, fiona  # noqa: F401,E401
import geopandas  # noqa: F401
libs = sorted({l.split()[-1] for l in open("/proc/self/maps") if any(k in l for k in ("libgdal", "libproj", "libgeos"))})
print(json.dumps(dict(libs=libs, proj=pyproj.proj_version_str, shapely_geos=shapely.geos_version_string,
                      rasterio_gdal=rasterio.__gdal_version__, pyogrio_gdal=pyogrio.__gdal_version_string__), indent=1))
EOF
step census_r_reticulate Rscript -e '
suppressMessages({library(sf); library(terra); library(gdalraster); library(vapour)})
gdal <- reticulate::import("osgeo.gdal"); rio <- reticulate::import("rasterio"); pyogrio <- reticulate::import("pyogrio")
p <- sub(".* ", "", readLines("/proc/self/maps"))
libs <- sort(unique(p[grepl("lib(gdal|proj|geos_c|geos)[.-]", p)]))
cat(jsonlite::toJSON(list(libs = libs, sf = as.list(sf::sf_extSoftVersion()), terra = terra::gdal(),
  gdalraster = gdalraster::gdal_version()[1], py_gdal = gdal$`__version__`, rasterio_gdal = rio$`__gdal_version__`),
  auto_unbox = TRUE, pretty = TRUE))'

# terra sets the GDAL_DATA config option to its bundled path, "" when it has none, for the whole
# process (src/RcppFunctions.cpp gdal_init); the same census with the Python modules imported first
step census_r_terra_last Rscript -e '
gdal <- reticulate::import("osgeo.gdal"); rio <- reticulate::import("rasterio"); pyogrio <- reticulate::import("pyogrio")
suppressMessages({library(sf); library(gdalraster); library(vapour); library(terra)})
p <- sub(".* ", "", readLines("/proc/self/maps"))
libs <- sort(unique(p[grepl("lib(gdal|proj|geos_c|geos)[.-]", p)]))
cat(jsonlite::toJSON(list(libs = libs, GDAL_DATA_after_terra = gdalraster::get_config_option("GDAL_DATA")), auto_unbox = TRUE, pretty = TRUE))'

# ---- stacgrid against odc-stac, GA tutorial load ----
step uv_odc $UV "odc-stac[botocore]>=0.5.2,<0.6" "pystac-client>=0.9,<0.10"
step odc_as_is $PY $X/ga-sar-ice/odc_load.py /out/odc_as_is.npz
step odc $OFF $PY $X/ga-sar-ice/odc_load.py /out/odc.npz
step sg_py $PY $X/stacgrid/ga_py.py $SG /out/sg_py.npz
step sg_r bash -c "Rscript $X/stacgrid/ga_r.R $SG /out/sg_r && $PY $X/stacgrid/r_to_npz.py /out/sg_r /out/sg_r.npz"
C=$X/ga-sar-ice/compare.py
step cmp_odc_py $PY $C /out/odc.npz /out/sg_py.npz
step cmp_odc_r $PY $C /out/odc.npz /out/sg_r.npz

# ---- NormCovar ----
COAST="https://ramadda.data.bas.ac.uk/repository/entry/get/add_coastline_medium_res_polygon_v7_12.shp.zip?entryid=synth%3Ac9c6d671-ad19-4a78-96b2-7d47e9bac46a%3AL2FkZF9jb2FzdGxpbmVfbWVkaXVtX3Jlc19wb2x5Z29uX3Y3XzEyLnNocC56aXA%3D"
step coast bash -c "mkdir -p /work/coast && cd /work/coast && curl -fsSL -o c.zip '$COAST' && echo 'b0172d698436f871f49339cea5c7155e3d98648360521cc4bbc44a026c0edc38  c.zip' | sha256sum -c && $PY -c 'import zipfile; zipfile.ZipFile(\"c.zip\").extractall(\".\")'"
SHP=/work/coast/add_coastline_medium_res_polygon_v7_12.shp
step py $PY $N/nc_gdal.py $SG $SHP /out/py.npz
step py_odc env NC_ODC_NODATA=1 $PY $N/nc_gdal.py $SG $SHP /out/py_odc.npz
step r bash -c "Rscript $N/nc_r.R $SG $SHP /out/r && $PY $N/r_to_npz.py /out/r /out/r.npz"
step rio_checks $PY $N/rio_checks.py
step gdal_checks $PY $N/gdal_checks.py $SHP
# the notebook: its extra packages added to the image's venv, as the gdal-r-ci README suggests
NC="normalized-covariance @ git+https://github.com/jlo031/normalized_covariance@d6843d2a31b57bb7e42ca531aff5077ea4a56fe4"
step uv_nb_latest $UV $NBX "odc-stac[botocore]>=0.5.2,<0.6" "odc-geo" "stac-geoparquet>=0.8,<0.9" loguru "$NC"
step nb_versions_latest $PY -c 'import odc.stac, odc.geo, xarray, rasterio, rioxarray, pandas; print("odc-stac", odc.stac.__version__, "odc-geo", odc.geo.__version__, "xarray", xarray.__version__, "rasterio", rasterio.__version__, "rioxarray", rioxarray.__version__, "pandas", pandas.__version__)'
step ref_latest $OFF $PY $N/nc_ref.py /out/ref_latest.npz
step uv_nb_052 $UV "odc-stac[botocore]==0.5.2"
step nb_versions_052 $PY -c 'import odc.stac, odc.geo; print("odc-stac", odc.stac.__version__, "odc-geo", odc.geo.__version__)'
step ref_052 $OFF $PY $N/nc_ref.py /out/ref_052.npz
NC_CMP=$N/compare.py
step cmp_py_r $PY $NC_CMP /out/py.npz /out/r.npz
step cmp_052_py $PY $NC_CMP /out/ref_052.npz /out/py.npz
step cmp_052_py_odc $PY $NC_CMP /out/ref_052.npz /out/py_odc.npz
step summary $PY - <<'PY'
import glob, json, os
for f in sorted(glob.glob("/out/cmp_*.log")):
    t = open(f).read()
    try:
        r = json.loads(t[t.index("{"):])
    except Exception:
        print(os.path.basename(f), t.strip()[-300:]); continue
    print(os.path.basename(f)[4:-4], {k: v["n_differ"] for k, v in r.items() if isinstance(v, dict) and "n_differ" in v})
PY
[ -f /out/r/normcovar_r.png ] && mv /out/r/normcovar_r.png /out/normcovar_r.png
rm -rf /out/r /out/sg_r /out/*.npz
{ command -v uv >/dev/null && uv pip freeze --python $PY || $PY -m pip freeze; } > /out/pip-freeze.txt 2>/dev/null
[ -f /opt/gdal-conda/packages.txt ] && cp /opt/gdal-conda/packages.txt /out/conda-packages.txt
true
