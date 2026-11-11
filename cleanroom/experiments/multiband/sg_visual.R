# The odc_visual.py load with stacgrid.R.
#   Rscript sg_visual.R <stacgrid dir> <outdir>     (<name>.tif per band, ids.txt)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
outdir <- a[2]; dir.create(outdir, showWarnings = FALSE)
bbox <- c(147.0, -42.9, 147.35, -42.85)
names_ <- c("visual.1", "visual.2", "visual.3", "visual", "red")
t0 <- Sys.time()
items <- stac_search("https://earth-search.aws.element84.com/v1", "sentinel-2-l2a", bbox = bbox,
                     datetime = "2021-12-01/2022-03-01")
grid <- grid_from_bbox(bbox, "EPSG:32755", 10)
groups <- group_items(items, "solar_day", grid = grid)
out <- stac_load(groups, names_, grid)
for (n in names_) write_stack(out[[n]], grid, file.path(outdir, paste0(n, ".tif")), names(groups))
writeLines(vapply(items, function(i) i$id, ""), file.path(outdir, "ids.txt"))
cat(sprintf('{"items": %d, "groups": %d, "types": "%s", "s": %.1f}\n', length(items), length(groups),
            paste(vapply(out, attr, "", "type"), collapse = ","), as.numeric(Sys.time() - t0, units = "secs")))
