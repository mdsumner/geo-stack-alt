#!/usr/bin/env bash
# Arm A-R (P3M): Ubuntu's R, then Linux binaries from Posit Package Manager (noble).
# Binaries do not bring system libraries: first try without them, then add runtime libs.
set -uo pipefail
source /cleanroom/arms/lib.sh
source /cleanroom/arms/r-lib.sh
export DEBIAN_FRONTEND=noninteractive
P3M=https://packagemanager.posit.co/cran/__linux__/noble/latest
step apt_r bash -c 'apt-get update -qq && apt-get install -y -qq r-base curl ca-certificates && R --version | head -1'
# P3M serves binaries only when the user agent names the R version and platform.
cat >> /usr/lib/R/etc/Rprofile.site <<'RP'
options(HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(),
  paste(getRversion(), R.version["platform"], R.version["arch"], R.version["os"])))
RP
step install_naive rinstall "$P3M"
step binaries_check bash -c 'grep -c -i "binary" /out/install_naive.log; grep -i -m3 "cannot open shared object" /out/install_naive.log'
step apt_runtime apt-get install -y -qq libgdal34t64 libgeos-c1t64 libproj25 libudunits2-0
step install_runtime rinstall "$P3M"
step probe_r Rscript /cleanroom/probe/probe.R /out/probe_r.json /out/dem_r.png
step probe_terra Rscript /cleanroom/probe/probe_terra.R /out/probe_terra.json
step sizes bash -c 'echo "rlib_bytes $(du -sbc /usr/local/lib/R/site-library | tail -1 | cut -f1)"; echo "rlib_files $(find /usr/local/lib/R/site-library -type f | wc -l)"'
grep -h -E "LOADED|MISSING" /out/install_*.log
