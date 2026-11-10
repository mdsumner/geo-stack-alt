# Shared R helpers for arm A-R. Source after lib.sh.
CRAN=${CRAN:-https://cloud.r-project.org}
RPKGS='c("sf", "terra", "gdalraster", "vapour", "wk", "ximage", "jsonlite")'
# Install, then report which of the packages load. Never fails the step on its own.
rinstall() {
  Rscript -e "options(repos = c(CRAN = '$1')); pk <- $RPKGS; install.packages(pk, Ncpus = 1)" \
    -e "ok <- vapply(pk, requireNamespace, logical(1), quietly = TRUE); print(ok); cat('LOADED', sum(ok), 'of', length(ok), '\n'); if (!all(ok)) cat('MISSING', names(ok)[!ok], '\n')"
}
