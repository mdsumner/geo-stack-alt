#!/usr/bin/env bash
# Arm C: all binaries from apt. Distro python3-gdal + numpy, and R packages from r2u (CRAN as
# .debs via bspm), so Python and R share the distro's one libgdal. Fast path only: no venv,
# no source builds. Uses the r2u setup script for this image's Ubuntu codename.
set -uo pipefail
source /cleanroom/arms/lib.sh
source /cleanroom/arms/r-lib.sh
export DEBIAN_FRONTEND=noninteractive
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
dpkg_kb() { dpkg-query -W -f='${Installed-Size}\n' | awk '{s+=$1} END{print s}'; }
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates'
k0=$(dpkg_kb)
step apt_python bash -c 'apt-get install -y -qq --no-install-recommends python3-gdal python3-numpy python3-matplotlib && python3 -c "from osgeo import gdal; print(gdal.__version__)"'
k1=$(dpkg_kb)
step r2u_setup bash -c "curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_${CODENAME}.sh | bash && R --version | head -1"
k2=$(dpkg_kb)
step install rinstall "$CRAN"
k3=$(dpkg_kb)
step probe_py python3 /cleanroom/probe/probe_gdal.py /out/probe_py.json
step probe_r Rscript /cleanroom/probe/probe.R /out/probe_r.json /out/dem_r.png
{
  echo "codename $CODENAME"
  echo "python_gdal_bytes $(( (k1 - k0) * 1024 ))"
  echo "r_base_bytes $(( (k2 - k1) * 1024 ))"
  echo "r_packages_bytes $(( (k3 - k2) * 1024 ))"
  echo "total_bytes $(( (k3 - k0) * 1024 ))"
} > /out/sizes.log
grep -h -E "LOADED|MISSING" /out/install.log; cat /out/sizes.log
