# The GA tutorial load with stacgrid.R; writes one multiband GeoTIFF per asset.
#   Rscript ga_r.R <stacgrid dir> <outdir> [overviews fuse]   (STACGRID_WORKERS: processes, default 8)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
outdir <- a[2]; dir.create(outdir, showWarnings = FALSE)
ovr <- if (length(a) > 3) a[3] else "AUTO"; fuse <- if (length(a) > 3) a[4] else "first"
Sys.setenv(AWS_NO_SIGN_REQUEST = "YES", AWS_REGION = "ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
bbox <- c(73.5, -69.1, 74.0, -68.8)
t0 <- Sys.time()
items <- stac_search("https://explorer.dev.dea.ga.gov.au/stac", "ga_s1_nrb_iw_hh_1", bbox = bbox,
                     datetime = "2021-01-01/2021-03-01")
grid <- grid_from_bbox(bbox, "EPSG:3031", 200)
groups <- group_items(items, "solar_day", grid = grid)
out <- stac_load(groups, c("hh_gamma0", "oa_layover_shadow_mask"), grid, overviews = ovr, fuse = fuse,
                 workers = as.integer(Sys.getenv("STACGRID_WORKERS", "8")))
for (k in names(out)) write_stack(out[[k]], grid, file.path(outdir, paste0(k, ".tif")), names(groups))
writeLines(sort(vapply(items, function(i) i$id, "")), file.path(outdir, "item_ids.txt"))
cat(length(items), "items,", length(groups), "groups, grid", grid$width, "x", grid$height, ",",
    round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s, workers", Sys.getenv("STACGRID_WORKERS", "8"), "\n")
