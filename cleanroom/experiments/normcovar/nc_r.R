# nc_ref.py with R: stacgrid.R for the EW load, gdalraster for the resample and the landmask, base R
# for the NormCovar arithmetic, ximage for the figure. See nc_gdal.py for what each step matches.
# The arithmetic is in double (R has no float32): the box filters are cumulative sums, the reference's
# are scipy's uniform_filter in float32. NC_ODC_NODATA=1 resamples with destination nodata 0, as the
# reference does through odc-geo on rasterio >= 1.5.1 (valid 0s become 1).
#   Rscript nc_r.R <stacgrid dir> <coastline .shp> <outdir>   (GeoTIFFs per product, pair.json, figure)
a <- commandArgs(TRUE)
source(file.path(a[1], "stacgrid.R"))
shp <- a[2]; outdir <- a[3]; dir.create(outdir, showWarnings = FALSE)
Sys.setenv(AWS_NO_SIGN_REQUEST = "YES", AWS_REGION = "ap-southeast-2", GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR")
bbox <- c(165.5, -77.85, 168.0, -77.45)
windows <- c(11, 21, 33); np_min <- -0.5; np_max <- 1.0; zoom <- 10
odc_nodata <- Sys.getenv("NC_ODC_NODATA") == "1"

## ---- NormCovar arithmetic (normalized_covariance d6843d2), on matrices m[x, y] ----
fill_nans <- function(m) { if (anyNA(m)) m[is.na(m)] <- mean(m, na.rm = TRUE); m }
box1 <- function(v, w) {         # scipy uniform_filter1d, mode="nearest", odd w, centred
  h <- w %/% 2; n <- length(v)
  cs <- c(0, cumsum(c(rep(v[1], h), v, rep(v[n], h))))
  (cs[seq_len(n) + w] - cs[seq_len(n)]) / w
}
box <- function(m, w) t(apply(apply(m, 2, box1, w = w), 1, box1, w = w))   # along x, then y
dev_from_local_mean <- function(m, w) { f <- fill_nans(m); f - box(f, w) }
local_var <- function(m, w) { f <- fill_nans(m); pmax(box(f^2, w) - box(f, w)^2, 0) }
normcovar <- function(m1, m2, w) {
  mv <- fill_nans((local_var(m1, w) + local_var(m2, w)) * 0.5)
  box(dev_from_local_mean(m1, w) * dev_from_local_mean(m2, w), w) / box(mv, w)
}
to_u8 <- function(m) { v <- floor((pmin(pmax(m, np_min), np_max) - np_min) / (np_max - np_min) * 255); v[is.na(v)] <- 0; v }

## ---- the geo steps, gdalraster ----
write_tif <- function(bands, grid, dst, type = "Byte") {   # bands: list of m[x, y]
  gdalraster::create("GTiff", dst, grid$width, grid$height, length(bands), type, options = "COMPRESS=DEFLATE")
  ds <- new(gdalraster::GDALRaster, dst, read_only = FALSE)
  ds$setGeoTransform(c(grid$extent[1], grid$res, 0, grid$extent[4], 0, -grid$res))
  ds$setProjection(gdalraster::srs_to_wkt(grid$crs))
  for (b in seq_along(bands)) ds$write(b, 0, 0, grid$width, grid$height, as.vector(bands[[b]]))
  ds$close(); invisible(dst)
}
read_tif <- function(src) {
  ds <- new(gdalraster::GDALRaster, src); on.exit(ds$close())
  nx <- ds$getRasterXSize(); ny <- ds$getRasterYSize()
  list(bands = lapply(seq_len(ds$getRasterCount()), function(b) matrix(ds$read(b, 0, 0, nx, ny, nx, ny), nx)),
       gt = ds$getGeoTransform())
}
zoom_warp <- function(src, dst, grid, method) {   # odc's xr_reproject onto geobox.zoom_to(shape / zoom)
  gdalraster::warp(src, dst, t_srs = grid$crs, quiet = TRUE,
                   cl_arg = c("-te", grid$extent, "-ts", max(1, round(grid$width / zoom)), max(1, round(grid$height / zoom)),
                              "-r", method, "-wo", "XSCALE=1", "-wo", "YSCALE=1", if (odc_nodata) c("-dstnodata", "0")))
  read_tif(dst)
}

t0 <- Sys.time()
grid <- grid_from_bbox(bbox, "EPSG:3031", 40)
items <- items_from_geoparquet(
  "https://dea-public-data-dev.s3.ap-southeast-2.amazonaws.com/experimental/baseline/pyrosar_gamma/ga_s1_nrb_ew_hh_hv_1_v2.parquet",
  "ga_s1_nrb_ew_hh_hv_1", datetime = "2019-01-01T00:00:00Z/2020-01-01T00:00:00Z", bbox = bbox)
groups <- group_items(items, "time")
when <- as.POSIXct(sub("Z$", "", names(groups)), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
pairs <- do.call(rbind, lapply(seq_along(when), function(i) if (i < length(when)) do.call(rbind, lapply((i + 1):length(when), function(j)
  data.frame(i = i, j = j, d = abs(as.numeric(difftime(when[j], when[i], units = "secs"))) / 86400)))))
pairs <- pairs[pairs$d >= 11.9 & pairs$d <= 12.1, ]
p <- pairs[1, ]
hh <- stac_load(groups[c(p$i, p$j)], "hh_gamma0", grid)$hh_gamma0
db <- 10 * log10(ifelse(hh > 0, hh, NA))
img1 <- matrix(db[, , 1], grid$width); img2 <- matrix(db[, , 2], grid$width)
t_load <- as.numeric(Sys.time() - t0, units = "secs")
t1 <- Sys.time()
nc <- lapply(windows, function(w) normcovar(img1, img2, w))
rgb <- lapply(nc, to_u8)
write_tif(rgb, grid, f_rgb <- file.path(outdir, "rgb.tif"))
rgb_res <- zoom_warp(f_rgb, file.path(outdir, "rgb_resampled.tif"), grid, "bilinear")
f_lm <- file.path(outdir, "landmask.tif")
# into an existing zero raster: gdal_rasterize creating its own output sets NoData = 0 on it (with or
# without -init; GDAL 3.13.3), which would make every water pixel nodata
write_tif(list(matrix(0, grid$width, grid$height)), grid, f_lm)
ds_lm <- new(gdalraster::GDALRaster, f_lm, read_only = FALSE)   # an open dataset: burnt in place
gdalraster::rasterize(shp, ds_lm, band = 1, burn_value = 1, quiet = TRUE)
ds_lm$close()
lm <- read_tif(f_lm)$bands[[1]]
lm_res <- zoom_warp(f_lm, file.path(outdir, "landmask_resampled.tif"), grid, "near")
rgb_lm <- lapply(rgb, function(b) ifelse(lm != 1, b, 0))
rgb_res_lm <- lapply(rgb_res$bands, function(b) ifelse(lm_res$bands[[1]] != 1, b, 0))
t_nc <- as.numeric(Sys.time() - t1, units = "secs")
write_tif(rgb_lm, grid, file.path(outdir, "rgb_landmasked.tif"))
# the resampled SAM input: rgb_resampled.tif's grid, the masked values
gdalraster::createCopy("GTiff", f_sam <- file.path(outdir, "rgb_resampled_landmasked.tif"), file.path(outdir, "rgb_resampled.tif"))
ds <- new(gdalraster::GDALRaster, f_sam, read_only = FALSE)
for (b in 1:3) ds$write(b, 0, 0, ds$getRasterXSize(), ds$getRasterYSize(), as.vector(rgb_res_lm[[b]]))
ds$close()
write_tif(c(list(img1, img2), nc), grid, file.path(outdir, "float.tif"), "Float64")
jsonlite::write_json(list(pair = names(groups)[c(p$i, p$j)], n_pairs = nrow(pairs), times = names(groups)),
                     file.path(outdir, "pair.json"), auto_unbox = TRUE)

## ---- figure: the NormCovar RGB, the landmask, and the SAM input, with ximage ----
png(file.path(outdir, "normcovar_r.png"), width = 1800, height = 640, res = 110)
op <- par(mfrow = c(1, 3), mar = c(2, 2, 2.5, 1))
arr <- function(bands) aperm(array(unlist(bands), c(dim(bands[[1]]), length(bands))), c(2, 1, 3)) / 255
ximage::ximage(arr(rgb), extent = grid$extent[c(1, 3, 2, 4)], asp = 1, axes = FALSE)
title(sprintf("NormCovar RGB (w %s)\n%s / %s", paste(windows, collapse = ", "), substr(names(groups)[p$i], 1, 10), substr(names(groups)[p$j], 1, 10)))
ximage::ximage(t(lm), extent = grid$extent[c(1, 3, 2, 4)], asp = 1, col = c("white", "grey40"), axes = FALSE)
title("landmask, grey = land (SCAR ADD v7.12)")
ximage::ximage(arr(rgb_res_lm), extent = grid$extent[c(1, 3, 2, 4)], asp = 1, axes = FALSE)
title(sprintf("SAM input: resampled /%d, landmasked%s", zoom, if (odc_nodata) " (dst nodata 0)" else ""))
par(op); dev.off()
cat(sprintf('{"items": %d, "groups": %d, "pairs": %d, "pair": ["%s", "%s"], "landmask_frac": %.6f, "load_s": %.1f, "normcovar_s": %.1f}\n',
            length(items), length(groups), nrow(pairs), names(groups)[p$i], names(groups)[p$j], mean(lm), t_load, t_nc))
