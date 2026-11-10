#!/usr/bin/env bash
# Arm A-R (source): Ubuntu's R, then install.packages() from CRAN, which builds from source.
# First with no system libraries (what a newcomer tries), then with the commonly documented
# -dev set (sf README), then the probes.
set -uo pipefail
source /cleanroom/arms/lib.sh
source /cleanroom/arms/r-lib.sh
export DEBIAN_FRONTEND=noninteractive
step apt_r bash -c 'apt-get update -qq && apt-get install -y -qq r-base curl ca-certificates && R --version | head -1'
step install_naive rinstall "$CRAN"
step apt_dev apt-get install -y -qq libgdal-dev libgeos-dev libproj-dev libudunits2-dev libsqlite3-dev libssl-dev libcurl4-openssl-dev libxml2-dev
step install_dev rinstall "$CRAN"
step probe_r Rscript /cleanroom/probe/probe.R /out/probe_r.json /out/dem_r.png
step probe_terra Rscript /cleanroom/probe/probe_terra.R /out/probe_terra.json
step sizes bash -c 'echo "rlib_bytes $(du -sbc /usr/local/lib/R/site-library | tail -1 | cut -f1)"; echo "rlib_files $(find /usr/local/lib/R/site-library -type f | wc -l)"; Rscript -e "ip <- installed.packages(lib.loc = .libPaths()[1]); cat(nrow(ip), \"packages in site-library\n\")"'
grep -h -E "LOADED|MISSING" /out/install_*.log
