# Probe the R default stack (sf + terra): versions, which GDAL/PROJ/GEOS, and the DEM job
# with terra::project (same target as probe.R / probe_gdal.py).
#
#   Rscript probe_terra.R out.json
args <- commandArgs(TRUE)
DEM <- paste0("https://copernicus-dem-30m.s3.amazonaws.com/",
              "Copernicus_DSM_COG_10_S43_00_E146_00_DEM/Copernicus_DSM_COG_10_S43_00_E146_00_DEM.tif")
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
res <- list(lang = "R", R = as.character(getRversion()))
for (p in c("sf", "terra", "gdalraster", "vapour", "wk", "ximage")) {
  res$packages[[p]] <- tryCatch(as.character(packageVersion(p)), error = function(e) NA)
}
res$sf_ext <- tryCatch(as.list(sf::sf_extSoftVersion()), error = function(e) paste("failed:", conditionMessage(e)))
res$terra_gdal <- tryCatch(terra::gdal(), error = function(e) paste("failed:", conditionMessage(e)))
res$terra <- tryCatch({
  t0 <- Sys.time()
  r <- terra::rast(paste0("/vsicurl/", DEM))
  tmpl <- terra::rast(terra::ext(1204000, 1244000, -4735000, -4695000), res = 40, crs = "EPSG:3577")
  p <- terra::project(r, tmpl, method = "bilinear")
  v <- terra::values(p, mat = FALSE)
  v <- v[is.finite(v)]
  list(seconds = round(as.numeric(Sys.time() - t0, units = "secs"), 2), dim = dim(p)[1:2],
       valid = length(v), min = round(min(v), 3), max = round(max(v), 3), mean = round(mean(v), 4))
}, error = function(e) paste("failed:", conditionMessage(e)))
p <- sub(".* ", "", readLines("/proc/self/maps"))
res$libs <- sort(unique(p[grepl("lib(gdal|proj|geos_c|geos)[.-]", p)]))
txt <- if (requireNamespace("jsonlite", quietly = TRUE)) {
  jsonlite::toJSON(res, auto_unbox = TRUE, pretty = TRUE)
} else capture.output(str(res))
writeLines(txt, args[1]); cat(txt, sep = "\n")
