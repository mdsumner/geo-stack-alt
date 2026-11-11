# The odc_s2.py load with stacgrid.R, raw and scaled.
#   Rscript sg_s2.R <stacgrid dir> <outdir>     (raw.tif, scaled.tif, ids.txt)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
outdir <- a[2]; dir.create(outdir, showWarnings = FALSE)
bbox <- c(147.3, -42.9, 147.35, -42.85)
t0 <- Sys.time()
items <- stac_search("https://earth-search.aws.element84.com/v1", "sentinel-2-l2a", bbox = bbox,
                     datetime = "2021-12-01/2022-03-01")
grid <- grid_from_bbox(bbox, "EPSG:32755", 10)
groups <- group_items(items, "solar_day", grid = grid)
raw <- stac_load(groups, "red", grid)$red
scaled <- stac_load(groups, "red", grid, scale = TRUE)$red
write_stack(raw, grid, file.path(outdir, "raw.tif"), names(groups))
write_stack(scaled, grid, file.path(outdir, "scaled.tif"), names(groups))
writeLines(vapply(items, function(i) i$id, ""), file.path(outdir, "ids.txt"))
cat(sprintf('{"items": %d, "groups": %d, "s": %.1f}\n', length(items), length(groups), as.numeric(Sys.time() - t0, units = "secs")))
