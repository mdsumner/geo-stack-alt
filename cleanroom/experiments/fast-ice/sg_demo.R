# sentinel_1_load_demo.ipynb's STAC loads (see odc_demo.py) with stacgrid.R.
#   Rscript sg_demo.R <stacgrid dir> <outdir>      (writes api.tif, pq.tif and id/label lists)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
outdir <- a[2]; dir.create(outdir, showWarnings = FALSE)
Sys.setenv(AWS_NO_SIGN_REQUEST = "YES", AWS_REGION = "ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
SAMPLE <- "/vsicurl/https://deant-data-public-dev.s3.ap-southeast-2.amazonaws.com/fast-ice/s1a_EW_20191217_hh_gamma0_db_sample.tif"
PARQUET <- "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet"
t0 <- Sys.time()
grid <- grid_from_raster(SAMPLE)
where <- grid_footprint(grid)
obs <- as.POSIXct("2019-12-17 11:25:53", tz = "UTC")
span <- function(secs) paste(format(obs - secs, "%Y-%m-%dT%H:%M:%S"), format(obs + secs, "%Y-%m-%dT%H:%M:%S"), sep = "/")
api_items <- stac_search("https://explorer.dev.dea.ga.gov.au/stac", "ga_s1_nrb_iw_hh_1", datetime = span(6 * 86400), intersects = where)
api_groups <- group_items(api_items, "sat:relative_orbit")
api <- stac_load(api_groups, "hh_gamma0", grid)$hh_gamma0
pq_items <- items_from_geoparquet(PARQUET, "ga_s1_nrb_ew_hh_hv_1", datetime = span(3600), intersects = where)
pq_groups <- group_items(pq_items, "sat:relative_orbit")
pq <- stac_load(pq_groups, "hh_gamma0", grid)$hh_gamma0
write_stack(api, grid, file.path(outdir, "api.tif"), names(api_groups))
write_stack(pq, grid, file.path(outdir, "pq.tif"), names(pq_groups))
writeLines(vapply(api_items, function(i) i$id, ""), file.path(outdir, "api_ids.txt"))
writeLines(vapply(pq_items, function(i) i$id, ""), file.path(outdir, "pq_ids.txt"))
cat(sprintf('{"api_items": %d, "api_groups": "%s", "pq_items": %d, "s": %.1f}\n', length(api_items),
            paste(names(api_groups), collapse = ","), length(pq_items), as.numeric(Sys.time() - t0, units = "secs")))
