# R version of aeo26-workshop presenters/make_examples.py (be22870): the same three example
# figures from data/, with gdalraster for GDAL and ximage + base graphics for drawing.
#
#   Rscript make_examples.R <aeo26 root> <outdir>
suppressPackageStartupMessages({ library(gdalraster); library(ximage) })
a <- commandArgs(TRUE)
DATA <- file.path(a[1], "data"); OUT <- a[2]; dir.create(OUT, showWarnings = FALSE)
YEARS <- c(2019, 2020, 2025)
S2_NODATA <- -999; SCALE <- 10000; STEP <- 2
SKY_BLUE <- "#56B4E9"; BLUISH_GREEN <- "#009E73"
SEVERITY <- list(`0` = c("Unburnt, or outside the fire", "#DDDDDD"), `2` = c("Low", "#F0E442"),
                 `3` = c("Moderate", "#E69F00"), `4` = c("High", "#D55E00"), `5` = c("Extreme", "#000000"))
S2_SOURCE <- "Sentinel-2 autumn (Mar–May) median composites: Digital Earth Australia, CC BY 4.0."
ALA_SOURCE <- "Greater glider records: Atlas of Living Australia."
FESM_SOURCE <- "Fire severity: NSW FESM 2019/20, DCCEEW, CC BY."
# ColorBrewer BrBG, the 11 colours matplotlib's "BrBG" interpolates
BRBG <- colorRampPalette(c("#543005", "#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#f5f5f5",
                           "#c7eae5", "#80cdc1", "#35978f", "#01665e", "#003c30"))(256)

## every band of a raster as a list of matrices (rows top-down), decimated like [::STEP, ::STEP]
read_bands <- function(path, step = STEP) {
  ds <- new(GDALRaster, path)
  on.exit(ds$close())
  nx <- ds$getRasterXSize(); ny <- ds$getRasterYSize()
  lapply(seq_len(ds$getRasterCount()), function(b) {
    m <- matrix(ds$read(b, 0, 0, nx, ny, nx, ny), ny, nx, byrow = TRUE)
    m[seq(1, ny, step), seq(1, nx, step), drop = FALSE]
  })
}
fesm_ds <- new(GDALRaster, file.path(DATA, "fire_severity_2019_20.tif"))
bb <- fesm_ds$bbox(); CRS <- fesm_ds$getProjection(); fesm_ds$close()
EXT <- bb[c(1, 3, 2, 4)]  # xmin, xmax, ymin, ymax: draw in map units (EPSG:3577 metres)

refl <- lapply(setNames(YEARS, YEARS), function(y) {
  lapply(read_bands(file.path(DATA, sprintf("sentinel2_%d.tif", y))), function(m) {
    m[m == S2_NODATA] <- NA; m / SCALE
  })
})
for (y in names(refl)) cat(sprintf("%s: reflectance %.3f to %.3f\n", y,
                                   min(unlist(refl[[y]]), na.rm = TRUE), max(unlist(refl[[y]]), na.rm = TRUE)))

g <- read.csv(file.path(DATA, "glider_records.csv"))
xy <- transform_xy(cbind(g$longitude, g$latitude), "EPSG:4326", "EPSG:3577")
pre <- g$year >= 2000 & g$year <= 2019; post <- g$year >= 2020
cat(sprintf("glider records: %d, of which 2000–2019: %d\n", nrow(g), sum(pre)))

## true north: degrees clockwise from map up, at the study-area centre
ctr <- transform_xy(cbind(mean(bb[c(1, 3)]), mean(bb[c(2, 4)])), CRS, "EPSG:4326")
nn <- transform_xy(rbind(ctr, ctr + c(0, 0.01)), "EPSG:4326", CRS)
north <- atan2(nn[2, 1] - nn[1, 1], nn[2, 2] - nn[1, 2]) * 180 / pi
cat(sprintf("true north: %.1f degrees clockwise of straight up\n", north))

scale_bar <- function(km = 5) {
  w <- diff(EXT[1:2]); h <- diff(EXT[3:4])
  x0 <- EXT[1] + 0.05 * w; y0 <- EXT[3] + 0.07 * h
  segments(x0, y0, x0 + km * 1000, y0, col = "white", lwd = 7, lend = 1)
  segments(x0, y0, x0 + km * 1000, y0, col = "black", lwd = 3, lend = 1)
  text(x0 + km * 500, y0 + 0.035 * h, paste(km, "km"), font = 2, cex = 0.9)
}
north_arrow <- function(angle) {
  w <- diff(EXT[1:2]); h <- diff(EXT[3:4]); len <- 0.09 * w
  x0 <- EXT[1] + 0.93 * w; y0 <- EXT[3] + 0.05 * h
  dx <- len * sin(angle * pi / 180); dy <- len * cos(angle * pi / 180)
  arrows(x0, y0, x0 + dx, y0 + dy, col = "white", lwd = 6, length = 0.12)
  arrows(x0, y0, x0 + dx, y0 + dy, col = "black", lwd = 2.5, length = 0.1)
  text(x0 + 1.25 * dx, y0 + 1.25 * dy, "N", font = 2, pos = 3, offset = 0.1)
}
caption <- function(txt) mtext(txt, side = 1, outer = TRUE, line = 0.8, cex = 0.8, col = "#444444")
q <- function(x, p) unname(quantile(x, p, na.rm = TRUE, type = 7))  # numpy nanpercentile

## 1. before_after.png: false colour (SWIR1, NIR, red), one 2-98 % stretch per band over all years
lo <- hi <- numeric(3)
for (k in 1:3) {  # k = output channel: SWIR1 (band 3), NIR (2), red (1)
  b <- c(3, 2, 1)[k]
  v <- unlist(lapply(refl, `[[`, b))
  lo[k] <- q(v, 0.02); hi[k] <- q(v, 0.98)
}
rgb_hex <- function(r) {
  ch <- lapply(1:3, function(k) {
    x <- (r[[c(3, 2, 1)[k]]] - lo[k]) / (hi[k] - lo[k])
    x[is.na(x)] <- 0; pmin(pmax(x, 0), 1)
  })
  matrix(rgb(ch[[1]], ch[[2]], ch[[3]]), nrow(ch[[1]]))
}
titles <- c(`2019` = "Autumn 2019: before the fire", `2020` = "Autumn 2020: after the fire",
            `2025` = "Autumn 2025: five years on")
png(file.path(OUT, "before_after.png"), width = 1500, height = 570, res = 100)
par(mfrow = c(1, 3), mar = c(0.3, 0.3, 2, 0.3), oma = c(2.2, 0, 2, 0))
for (y in names(refl)) {
  ximage(rgb_hex(refl[[y]]), extent = EXT, asp = 1, axes = FALSE)
  title(titles[[y]], font.main = 1, cex.main = 1.3)
  if (y == "2019") {
    points(xy[pre, 1], xy[pre, 2], pch = 21, bg = "white", col = "black", cex = 0.7, lwd = 0.6)
    legend("topright", "Greater glider records, 2000–2019", pch = 21, pt.bg = "white",
           bg = adjustcolor("white", 0.85), cex = 0.9)
    scale_bar(); north_arrow(north)
  }
}
mtext(paste("Tallaganda study area, NSW · false colour: SWIR1 (red), NIR (green), red (blue)",
            "· burnt forest shows as dark magenta"), outer = TRUE, line = 0.5)
caption(paste(S2_SOURCE, ALA_SOURCE, "One colour stretch for all three years."))
invisible(dev.off())

## 2. ndvi_change.png: two panels on one diverging scale, -0.6 to 0.6
ndvi <- lapply(refl, function(r) (r[[2]] - r[[1]]) / (r[[2]] + r[[1]]))
panels <- list(`2019 → 2020: the fire` = ndvi[["2020"]] - ndvi[["2019"]],
               `2020 → 2025: recovery` = ndvi[["2025"]] - ndvi[["2020"]])
png(file.path(OUT, "ndvi_change.png"), width = 1040, height = 660, res = 100)
layout(matrix(c(1, 2, 3, 3), 2, byrow = TRUE), heights = c(1, 0.16))
par(mar = c(0.3, 0.3, 2, 0.3), oma = c(2.2, 0, 2, 0))
for (nm in names(panels)) {
  x <- pmin(pmax(panels[[nm]], -0.6), 0.6)
  ximage(x, extent = EXT, zlim = c(-0.6, 0.6), col = BRBG, asp = 1, axes = FALSE)
  title(nm, font.main = 1, cex.main = 1.3)
  if (nm == names(panels)[1]) { scale_bar(); north_arrow(north) }
}
par(mar = c(2.8, 8, 0.6, 8))
image(seq(-0.6, 0.6, length.out = 256), 1, matrix(seq(-0.6, 0.6, length.out = 256)), col = BRBG,
      axes = FALSE, xlab = "", ylab = "")
axis(1); box()
mtext("Change in NDVI (no units): brown = less green, green = greener", 1, line = 2, cex = 0.8)
mtext("Tallaganda study area, NSW · change in greenness (NDVI)", outer = TRUE, line = 0.5)
caption(S2_SOURCE)
invisible(dev.off())

## 3. fire_severity_and_gliders.png: severity classes with the glider records on top
fesm <- read_bands(file.path(DATA, "fire_severity_2019_20.tif"))[[1]]
writeBin(as.integer(t(fesm)), file.path(OUT, "fesm_decimated.int32"), size = 4)  # for the pixel check
cols <- matrix(NA_character_, nrow(fesm), ncol(fesm))
for (code in names(SEVERITY)) cols[fesm == as.integer(code)] <- SEVERITY[[code]][2]
png(file.path(OUT, "fire_severity_and_gliders.png"), width = 1000, height = 730, res = 100)
par(mar = c(0.5, 0.5, 0.5, 18), oma = c(2.2, 0, 2.5, 0))
ximage(cols, extent = EXT, asp = 1, axes = FALSE)
points(xy[pre, 1], xy[pre, 2], pch = 21, bg = SKY_BLUE, col = "black", cex = 0.8, lwd = 0.5)
points(xy[post, 1], xy[post, 2], pch = 24, bg = BLUISH_GREEN, col = "black", cex = 0.8, lwd = 0.5)
scale_bar(); north_arrow(north)
mtext("Tallaganda study area, NSW · fire severity and greater glider records", outer = TRUE, line = 0.8, cex = 1.2)
par(xpd = NA)
legend(EXT[2] + 0.02 * diff(EXT[1:2]), EXT[4],
       c(vapply(SEVERITY, `[`, "", 1), "Glider records, 2000–2019", "Glider records, 2020 on"),
       pch = c(rep(22, 5), 21, 24), pt.bg = c(vapply(SEVERITY, `[`, "", 2), SKY_BLUE, BLUISH_GREEN),
       col = c(rep("#888888", 5), "black", "black"), pt.cex = c(rep(2, 5), 1, 1),
       title = "Fire severity, 2019–20", title.adj = 0, bty = "n", cex = 0.95)
caption(paste(FESM_SOURCE, ALA_SOURCE))
invisible(dev.off())
for (f in c("before_after.png", "ndvi_change.png", "fire_severity_and_gliders.png"))
  cat(sprintf("wrote %s (%.0f KB)\n", f, file.size(file.path(OUT, f)) / 1024))
