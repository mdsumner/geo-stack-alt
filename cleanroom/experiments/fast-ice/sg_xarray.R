# fast_ice_from_stac_xarray.ipynb's two loads (see odc_xarray.py) with stacgrid.R.
#   Rscript sg_xarray.R <stacgrid dir> <outdir>      (writes ew.tif, iw.tif and id/label lists)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
outdir <- a[2]; dir.create(outdir, showWarnings = FALSE)
Sys.setenv(AWS_NO_SIGN_REQUEST = "YES", AWS_REGION = "ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
bbox <- c(165.5, -77.85, 168.0, -77.45)
grid <- grid_from_bbox(bbox, "EPSG:3031", 40)
t0 <- Sys.time()
# EW: the notebook filters the GeoParquet with datetime >= "2019-01-01" and <= "2020-01-01" (midnight)
ew_items <- items_from_geoparquet(
  "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet",
  "ga_s1_nrb_ew_hh_hv_1", datetime = "2019-01-01T00:00:00Z/2020-01-01T00:00:00Z", bbox = bbox)
ew_groups <- group_items(ew_items, "time")
ew <- stac_load(ew_groups, "hh_gamma0", grid)$hh_gamma0
t_ew <- as.numeric(Sys.time() - t0, units = "secs")
t1 <- Sys.time()
# IW: the notebook searches with intersects=AOI_BBOX.boundary(), the bbox outline as a LineString
ring <- list(c(bbox[1], bbox[2]), c(bbox[3], bbox[2]), c(bbox[3], bbox[4]), c(bbox[1], bbox[4]), c(bbox[1], bbox[2]))
iw_items <- stac_search("https://explorer.dev.dea.ga.gov.au/stac", "ga_s1_nrb_iw_hh_1",
                        datetime = "2019-01-01/2020-01-01", intersects = list(type = "LineString", coordinates = ring))
iw_groups <- group_items(iw_items, "solar_day", grid = grid)
iw <- stac_load(iw_groups, "hh_gamma0", grid)$hh_gamma0
t_iw <- as.numeric(Sys.time() - t1, units = "secs")
write_stack(ew, grid, file.path(outdir, "ew.tif"), names(ew_groups))
write_stack(iw, grid, file.path(outdir, "iw.tif"), names(iw_groups))
writeLines(vapply(ew_items, function(i) i$id, ""), file.path(outdir, "ew_ids.txt"))
writeLines(sort(vapply(iw_items, function(i) i$id, "")), file.path(outdir, "iw_ids.txt"))
cat(sprintf('{"ew_items": %d, "ew_groups": %d, "ew_s": %.1f, "iw_items": %d, "iw_groups": %d, "iw_s": %.1f}\n',
            length(ew_items), length(ew_groups), t_ew, length(iw_items), length(iw_groups), t_iw))
