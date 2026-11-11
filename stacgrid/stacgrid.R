# stacgrid: STAC items -> groups -> one grid, with gdalraster and jsonlite.
#
# The R twin of stacgrid.py: same functions, same defaults, same pixels. The defaults
# reproduce odc-stac's load (overviews on, first valid pixel wins); overviews = "NONE" with
# fuse = "last" reproduces GDAL's STACIT mosaic.
#
#   source("stacgrid.R")
#   items  <- stac_search("https://explorer.dev.dea.ga.gov.au/stac", "ga_s1_nrb_iw_hh_1",
#                         bbox = c(73.5, -69.1, 74.0, -68.8), datetime = "2021-01-01/2021-03-01")
#   grid   <- grid_from_bbox(c(73.5, -69.1, 74.0, -68.8), "EPSG:3031", 200)
#   groups <- group_items(items, "solar_day")
#   out    <- stac_load(groups, "hh_gamma0", grid)   # list(hh_gamma0 = array [x, y, time])

expand_datetime <- function(d) {
  p <- strsplit(d, "/", fixed = TRUE)[[1]]
  if (!grepl("T", p[1])) p[1] <- paste0(p[1], "T00:00:00Z")
  if (length(p) > 1 && !grepl("T", p[2])) p[2] <- paste0(p[2], "T23:59:59Z")
  paste(p, collapse = "/")
}

stac_search <- function(endpoint, collections, bbox = NULL, datetime = NULL, limit = 100, ...) {
  q <- c(list(collections = paste(collections, collapse = ","), limit = limit), list(...))
  if (!is.null(bbox)) q$bbox <- paste(format(bbox, digits = 15), collapse = ",")
  if (!is.null(datetime)) q$datetime <- expand_datetime(datetime)
  enc <- function(x) utils::URLencode(as.character(x), reserved = TRUE)
  url <- paste0(sub("/$", "", endpoint), "/search?",
                paste(names(q), gsub("%2C", ",", gsub("%3A", ":", gsub("%2F", "/", vapply(q, enc, "")))),
                      sep = "=", collapse = "&"))
  items <- list()
  while (!is.null(url)) {
    page <- jsonlite::fromJSON(url, simplifyVector = FALSE)
    items <- c(items, page$features)
    nxt <- Filter(function(k) identical(k$rel, "next") && (is.null(k$method) || k$method == "GET"), page$links)
    url <- if (length(nxt)) nxt[[1]]$href else NULL
  }
  items
}

grid_from_bbox <- function(bbox, crs, res, bbox_crs = "EPSG:4326", densify = 21) {
  b <- gdalraster::transform_bounds(bbox, bbox_crs, crs, densify_pts = densify)
  e <- c(floor(b[1] / res) * res, floor(b[2] / res) * res, ceiling(b[3] / res) * res, ceiling(b[4] / res) * res)
  list(crs = crs, extent = e, res = res,
       width = as.integer(round((e[3] - e[1]) / res)), height = as.integer(round((e[4] - e[2]) / res)))
}

item_time <- function(item) as.POSIXct(sub("Z$", "", item$properties$datetime), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")

solar_day <- function(item) {
  lon <- (item$bbox[[1]] + item$bbox[[3]]) / 2
  format(item_time(item) + lon / 15 * 3600, "%Y-%m-%d", tz = "UTC")
}

group_items <- function(items, by = "solar_day") {
  key <- if (is.function(by)) by else switch(by,
    solar_day = solar_day,
    time = function(i) i$properties$datetime,
    function(i) as.character(i$properties[[by]]))
  items <- items[order(vapply(items, function(i) as.numeric(item_time(i)), 0))]
  k <- vapply(items, key, "")
  g <- split(items, factor(k, levels = unique(k)))
  g[order(names(g))]
}

asset_href <- function(item, asset) {
  h <- item$assets[[asset]]$href
  if (startsWith(h, "s3://")) return(paste0("/vsis3/", substring(h, 6)))
  if (grepl("^https?://", h)) return(paste0("/vsicurl/", h))
  h
}

warp_to_grid <- function(src, grid, resampling = "near", overviews = "AUTO") {
  # pid + tempfile(): unique per forked worker, and leaves the R random stream alone
  tf <- sprintf("/vsimem/stacgrid_%d_%s.tif", Sys.getpid(), basename(tempfile("")))
  on.exit(gdalraster::vsi_unlink(tf))
  gdalraster::warp(src, tf, t_srs = grid$crs, quiet = TRUE,
                   cl_arg = c("-te", grid$extent, "-ts", grid$width, grid$height,
                              "-r", resampling, "-ovr", overviews))
  ds <- new(gdalraster::GDALRaster, tf)
  on.exit(ds$close(), add = TRUE, after = FALSE)
  v <- ds$read(1, 0, 0, grid$width, grid$height, grid$width, grid$height)
  list(values = v, nodata = ds$getNoDataValue(1), type = ds$getDataTypeName(1))
}

# Each asset as an array [x, y, group] (x fastest, rows top-down, as GDAL reads).
# workers: warps run in that many forked processes (parallel::mclapply; serial on Windows).
# Results are merged in item order whatever order they finish in, so pixels don't depend on it.
stac_load <- function(groups, assets, grid, resampling = "near", overviews = "AUTO", fuse = "first",
                      workers = 8L) {
  jobs <- do.call(rbind, lapply(assets, function(asset) do.call(rbind, lapply(seq_along(groups), function(g)
    data.frame(asset = asset, g = g, src = vapply(groups[[g]], asset_href, "", asset = asset))))))
  warp <- function(src) warp_to_grid(src, grid, resampling, overviews)
  res <- if (workers > 1L && .Platform$OS.type == "unix") {
    parallel::mclapply(jobs$src, warp, mc.cores = workers, mc.preschedule = FALSE)
  } else lapply(jobs$src, warp)
  # mclapply returns a try-error for a failed warp, NULL for a worker that died
  bad <- vapply(res, function(r) is.null(r) || inherits(r, "try-error"), NA)
  if (any(bad)) stop("warp failed: ", jobs$src[bad][1], ": ", format(res[bad][[1]]))
  out <- list()
  for (asset in assets) {
    arr <- array(NA_real_, c(grid$width, grid$height, length(groups)))
    for (g in seq_along(groups)) {
      acc <- NULL
      for (w in res[jobs$asset == asset & jobs$g == g]) {
        a <- w$values
        valid <- if (is.na(w$nodata)) !is.na(a) else !is.na(a) & a != w$nodata
        if (is.null(acc)) {
          acc <- a; accv <- valid
          acc[!valid] <- w$nodata
        } else {
          take <- if (fuse == "first") valid & !accv else valid
          acc[take] <- a[take]
          accv <- accv | valid
        }
      }
      arr[, , g] <- acc
    }
    attr(arr, "type") <- w$type
    attr(arr, "nodata") <- w$nodata
    out[[asset]] <- arr
  }
  attr(out, "groups") <- names(groups)
  attr(out, "grid") <- grid
  out
}

# Write one asset's array as a multiband GeoTIFF, a band per group, labelled.
write_stack <- function(arr, grid, dst, labels) {
  gdalraster::create("GTiff", dst, grid$width, grid$height, dim(arr)[3], attr(arr, "type"),
                     options = c("COMPRESS=DEFLATE", "TILED=YES"))
  ds <- new(gdalraster::GDALRaster, dst, read_only = FALSE)
  ds$setGeoTransform(c(grid$extent[1], grid$res, 0, grid$extent[4], 0, -grid$res))
  ds$setProjection(gdalraster::srs_to_wkt(grid$crs))
  for (b in seq_len(dim(arr)[3])) {
    if (!is.na(attr(arr, "nodata"))) ds$setNoDataValue(b, attr(arr, "nodata"))
    ds$write(b, 0, 0, grid$width, grid$height, as.vector(arr[, , b]))
    ds$setDescription(b, labels[b])
  }
  ds$close()
  invisible(dst)
}
