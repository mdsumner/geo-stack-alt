#!/usr/bin/env bash
# Arm A-R (r2u): CRAN as Ubuntu binaries via apt (eddelbuettel/r2u). The official setup script
# adds the r2u and CRAN apt repos, installs R from CRAN, and enables bspm so that
# install.packages() installs .deb packages, with their system libraries, through apt.
set -uo pipefail
source /cleanroom/arms/lib.sh
source /cleanroom/arms/r-lib.sh
export DEBIAN_FRONTEND=noninteractive
dpkg_kb() { dpkg-query -W -f='${Installed-Size}\n' | awk '{s+=$1} END{print s}'; }
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends curl ca-certificates'
base_kb=$(dpkg_kb)
step r2u_setup bash -c 'curl -fsSL https://raw.githubusercontent.com/eddelbuettel/r2u/master/inst/scripts/add_cranapt_noble.sh | bash && R --version | head -1'
r_kb=$(dpkg_kb)
step install rinstall "$CRAN"
pk_kb=$(dpkg_kb)
step probe_r Rscript /cleanroom/probe/probe.R /out/probe_r.json /out/dem_r.png
step probe_terra Rscript /cleanroom/probe/probe_terra.R /out/probe_terra.json
{
  echo "r_base_installed_bytes $(( (r_kb - base_kb) * 1024 ))"
  echo "packages_installed_bytes $(( (pk_kb - r_kb) * 1024 ))  (R packages + system libs via apt)"
  echo "rlib_files $(find /usr/lib/R/site-library -type f | wc -l)"
  echo "debs_r_cran $(dpkg -l 'r-cran-*' 2>/dev/null | grep -c '^ii')"
} > /out/sizes.log
grep -h -E "LOADED|MISSING" /out/install.log; cat /out/sizes.log
