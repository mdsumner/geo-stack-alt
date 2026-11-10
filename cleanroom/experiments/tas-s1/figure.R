# R version of the `figure` step of tas_s1_change.py: same decimated read, same statistics,
# same two PNGs, drawn with ximage and base graphics. gdalraster does the GDAL work.
#
#   Rscript figure.R <mosaic.tif> <outdir> [max_px]
library(gdalraster)
library(ximage)
options(scipen = 10)  # plain axis numbers, as ticklabel_format(style = "plain")
args <- commandArgs(TRUE)
src <- args[1]; outdir <- args[2]
max_px <- if (length(args) > 2) as.integer(args[3]) else 4000L
BANDS <- c("vh_apr_oct", "vv_apr_oct", "vh_sep_oct", "vv_sep_oct")
res_m <- sub(".*_([0-9]+m)\\.tif$", "\\1", basename(src))

## decimated read: gdal_translate -outsize -r average is GDAL's averaging RasterIO, the
## same thing the Python side gets from ReadAsArray(buf_xsize, buf_ysize, resample_alg=Average)
ds <- new(GDALRaster, src)
nx <- ds$getRasterXSize(); ny <- ds$getRasterYSize()
fac <- max(1L, ceiling(max(nx, ny) / max_px))
bx <- nx %/% fac; by <- ny %/% fac
ext <- ds$bbox()[c(1, 3, 2, 4)]  # xmin, xmax, ymin, ymax
ds$close()
small <- tempfile(fileext = ".tif")
translate(src, small, cl_arg = c("-outsize", bx, by, "-r", "average"), quiet = TRUE)
ds <- new(GDALRaster, small)
a <- lapply(1:4, function(b) matrix(ds$read(b, 0, 0, bx, by, bx, by), by, bx, byrow = TRUE))
ds$close()

## statistics, matching numpy: percentile = quantile type 7, std with ddof = 0
stats <- setNames(lapply(a, function(x) {
  v <- x[is.finite(x)]
  if (!length(v)) return(list(n = 0L))
  list(n = length(v), p01 = unname(quantile(v, 0.01)), median = median(v),
       p99 = unname(quantile(v, 0.99)), sd = sqrt(mean((v - mean(v))^2)),
       frac_lt_minus3 = mean(v < -3), frac_gt_plus3 = mean(v > 3))
}), BANDS)
writeLines(jsonlite::toJSON(stats, auto_unbox = TRUE, digits = NA, pretty = TRUE),
           file.path(outdir, sprintf("tas_s1_change_stats_%s_r.json", res_m)))

## maps: 2 x 2 panels plus a colour bar, RdBu clamped to -4..4 dB (as vmin/vmax)
titles <- c("VH change, April -> October 2026", "VV change, April -> October 2026",
            "VH change, September -> October 2026 (12-day reference)",
            "VV change, September -> October 2026 (12-day reference)")
pal <- hcl.colors(256, "RdBu")
png(file.path(outdir, sprintf("tas_s1_change_%s_r.png", res_m)), width = 1320, height = 1210, res = 110)
layout(matrix(c(1, 2, 5, 3, 4, 5), 2, byrow = TRUE), widths = c(1, 1, 0.18))
par(mar = c(4, 4.5, 2, 1), oma = c(0, 0, 2, 0), mgp = c(2.5, 0.7, 0))
for (i in 1:4) {
  x <- pmin(pmax(a[[i]], -4), 4)
  ximage(x, extent = ext, zlim = c(-4, 4), col = pal, asp = 1,
         xlab = "Easting (m, MGA zone 55)", ylab = "Northing (m)", cex.axis = 0.7)
  title(titles[i], cex.main = 0.9, font.main = 1)
  x0 <- ext[1] + 0.05 * diff(ext[1:2]); y0 <- ext[3] + 0.05 * diff(ext[3:4])
  segments(x0, y0, x0 + 50000, y0, lwd = 4)
  text(x0 + 25000, y0 + 6000, "50 km", cex = 0.7, pos = 3, offset = 0)
  xn <- ext[2] - 0.07 * diff(ext[1:2]); yn <- ext[4] - 0.12 * diff(ext[3:4])
  arrows(xn, yn, xn, yn + 30000, length = 0.08, lwd = 1.5)
  text(xn, yn, "N", pos = 1)
}
par(mar = c(20, 1, 20, 4))
image(1, seq(-4, 4, length.out = 256), matrix(seq(-4, 4, length.out = 256), 1), col = pal,
      axes = FALSE, xlab = "", ylab = "")
axis(4, las = 1); box()
mtext("Backscatter change (dB); blue = brighter later, red = darker later", 4, line = 2.5, cex = 0.7)
mtext("DEA Sentinel-1 NRB gamma0 change over Tasmania, 2026 (burst-wise, layover/shadow masked)",
      outer = TRUE, cex = 1)
dev.off()

## histogram: step outlines of density, 0.1 dB bins from -8 to 8
png(file.path(outdir, sprintf("tas_s1_change_hist_%s_r.png", res_m)), width = 770, height = 440, res = 110)
par(mar = c(4, 4, 2, 1))
br <- seq(-8, 8, length.out = 161)
h <- lapply(a, function(x) { v <- x[is.finite(x) & x >= -8 & x <= 8]; hist(v, br, plot = FALSE) })
cols <- c("#1f77b4", "#ff7f0e", "#2ca02c", "#d62728")  # matplotlib tab10, first four
plot(NA, xlim = c(-8, 8), ylim = c(0, max(sapply(h, function(z) max(z$density)))),
     xlab = "Change (dB)", ylab = "Density", main = "Distribution of backscatter change, Tasmania 2026",
     font.main = 1, cex.main = 1)
for (i in 1:4) lines(br, c(h[[i]]$density, 0), type = "s", col = cols[i])
legend("topright", BANDS, col = cols, lwd = 1, cex = 0.7, bty = "n")
dev.off()
cat(jsonlite::toJSON(stats, auto_unbox = TRUE, digits = 6, pretty = TRUE), "\n")
