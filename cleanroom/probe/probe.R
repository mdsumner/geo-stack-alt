# Probe the R side: versions, drivers, which libgdal is loaded, and the same job as
# probe_gdal.py (warp the DEM COG to a 40 km Albers box at 40 m), done twice: with
# vapour::gdal_raster_data and with gdalraster::warp. Draws the result with ximage.
#
#   Rscript probe.R out.json out.png
args <- commandArgs(TRUE)
DEM <- paste0("https://copernicus-dem-30m.s3.amazonaws.com/",
              "Copernicus_DSM_COG_10_S43_00_E146_00_DEM/Copernicus_DSM_COG_10_S43_00_E146_00_DEM.tif")
CRS <- "EPSG:3577"
EXTENT <- c(1204000, 1244000, -4735000, -4695000)  # xmin, xmax, ymin, ymax (vapour order)
RES <- 40
DRIVERS <- c("GTiff", "COG", "VRT", "netCDF", "HDF5", "Zarr", "Parquet", "GPKG", "FlatGeobuf",
             "GeoJSON", "ESRI Shapefile", "JP2OpenJPEG", "KEA", "PDF", "STACIT", "GTI",
             "PostgreSQL", "OpenFileGDB", "LIBKML", "WMS", "WMTS")
Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")

summarise <- function(x, nodata = NA) {
  x <- as.numeric(x)
  ok <- is.finite(x) & (is.na(nodata) | x != nodata)
  v <- x[ok]
  list(valid = sum(ok), min = round(min(v), 3), max = round(max(v), 3), mean = round(mean(v), 4))
}

res <- list(lang = "R", R = as.character(getRversion()))
for (p in c("gdalraster", "vapour", "wk", "ximage")) {
  res$packages[[p]] <- tryCatch(as.character(packageVersion(p)), error = function(e) NA)
}
res$gdal_vapour <- vapour::vapour_gdal_version()
res$gdal_gdalraster <- gdalraster::gdal_version()[1]
drv <- vapour::vapour_all_drivers()$driver
res$driver_count <- length(drv)
res$drivers <- as.list(setNames(DRIVERS %in% drv, DRIVERS))

## vapour: warp straight to an R vector
t0 <- Sys.time()
v <- vapour::gdal_raster_data(DEM, target_crs = CRS, target_ext = EXTENT, target_res = RES,
                              resample = "bilinear")
res$vapour_seconds <- round(as.numeric(Sys.time() - t0, units = "secs"), 2)
res$vapour <- c(list(dim = attr(v, "dimension")), summarise(v[[1]]))

## gdalraster: GDAL's own warp to a MEM-like temp file, then read
t0 <- Sys.time()
tf <- tempfile(fileext = ".tif")
ok <- gdalraster::warp(paste0("/vsicurl/", DEM), tf, t_srs = CRS,
                       cl_arg = c("-te", EXTENT[c(1, 3, 2, 4)], "-tr", RES, RES, "-r", "bilinear"),
                       quiet = TRUE)
ds <- new(gdalraster::GDALRaster, tf)
g <- gdalraster::read_ds(ds)
nd <- ds$getNoDataValue(1)
ds$close()
res$gdalraster_seconds <- round(as.numeric(Sys.time() - t0, units = "secs"), 2)
res$gdalraster <- c(list(dim = attr(g, "gis")$dim[1:2]), summarise(g, nd))

## ximage: draw it
res$png <- tryCatch({
  png(args[2], width = 800, height = 800)
  ximage::ximage(matrix(v[[1]], attr(v, "dimension")[2], byrow = TRUE), extent = EXTENT,
                 asp = 1, col = hcl.colors(64, "Batlow"))
  dev.off()
  "ok"
}, error = function(e) paste("failed:", conditionMessage(e)))
res$capabilities_png <- capabilities("png")
res$capabilities_cairo <- capabilities("cairo")

maps <- readLines("/proc/self/maps")
p <- sub(".* ", "", maps)
res$libs <- sort(unique(p[grepl("lib(gdal|proj|geos_c|geos)[.-]", p)]))

writeLines(jsonlite::toJSON(res, auto_unbox = TRUE, pretty = TRUE), args[1])
cat(readLines(args[1]), sep = "\n")
