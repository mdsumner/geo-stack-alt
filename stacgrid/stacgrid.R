# stacgrid: STAC items -> groups -> one grid, with gdalraster and jsonlite (and curl for POST searches).
#
# The R twin of stacgrid.py: same functions, same defaults, same pixels. The defaults
# reproduce odc-stac's load (overviews on, first valid pixel wins); overviews = "NONE" with
# fuse = "last" reproduces GDAL's STACIT mosaic.
#
#   source("stacgrid.R")
#   items  <- stac_search("https://explorer.dev.dea.ga.gov.au/stac", "ga_s1_nrb_iw_hh_1",
#                         bbox = c(73.5, -69.1, 74.0, -68.8), datetime = "2021-01-01/2021-03-01")
#   grid   <- grid_from_bbox(c(73.5, -69.1, 74.0, -68.8), "EPSG:3031", 200)
#   groups <- group_items(items, "solar_day", grid = grid)
#   out    <- stac_load(groups, "hh_gamma0", grid)   # list(hh_gamma0 = array [x, y, time])

# '2021-01-01/2021-03-01' -> full-day RFC 3339 interval, as pystac-client does; a date-time
# with no zone is taken as UTC.
expand_datetime <- function(d) {
  one <- function(x, end) {
    if (is.na(x) || x == "" || x == "..") return(x)
    if (!grepl("T", x)) return(paste0(x, if (end) "T23:59:59Z" else "T00:00:00Z"))
    if (grepl("Z$", x) || grepl("[+-]", substring(x, 11))) x else paste0(x, "Z")
  }
  p <- strsplit(d, "/", fixed = TRUE)[[1]]
  if (length(p) == 1) return(one(p[1], FALSE))
  paste(one(p[1], FALSE), one(p[2], TRUE), sep = "/")
}

parse_time <- function(x) {
  x <- sub("Z$", "", sub("([+-]00:?00)$", "", x))
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
}

interval <- function(d) {
  p <- strsplit(expand_datetime(d), "/", fixed = TRUE)[[1]]
  lo <- if (p[1] %in% c("", "..")) -Inf else as.numeric(parse_time(p[1]))
  hi <- if (length(p) == 1) lo else if (p[2] %in% c("", "..")) Inf else as.numeric(parse_time(p[2]))
  c(lo, hi)
}

# All items of a STAC API /search, following "next" links. GET, or POST when `intersects` (a
# GeoJSON geometry as a list) is given: the API wants that as JSON in a POST body (DEA's explorer
# takes POST without advertising it). POST needs the curl package.
stac_search <- function(endpoint, collections, bbox = NULL, datetime = NULL, limit = 100,
                        intersects = NULL, ...) {
  url <- paste0(sub("/$", "", endpoint), "/search")
  if (is.null(intersects)) {
    q <- c(list(collections = paste(collections, collapse = ","), limit = limit), list(...))
    if (!is.null(bbox)) q$bbox <- paste(format(bbox, digits = 15), collapse = ",")
    if (!is.null(datetime)) q$datetime <- expand_datetime(datetime)
    enc <- function(x) utils::URLencode(as.character(x), reserved = TRUE)
    url <- paste0(url, "?", paste(names(q), gsub("%2C", ",", gsub("%3A", ":", gsub("%2F", "/", vapply(q, enc, "")))),
                                  sep = "=", collapse = "&"))
    body <- NULL
  } else {
    body <- c(list(collections = as.list(collections), limit = limit, intersects = intersects), list(...))
    if (!is.null(bbox)) body$bbox <- as.list(bbox)
    if (!is.null(datetime)) body$datetime <- expand_datetime(datetime)
  }
  items <- list()
  while (!is.null(url)) {
    page <- if (is.null(body)) jsonlite::fromJSON(url, simplifyVector = FALSE) else {
      h <- curl::new_handle(postfields = as.character(jsonlite::toJSON(body, auto_unbox = TRUE, digits = NA)))
      curl::handle_setheaders(h, "Content-Type" = "application/json")
      r <- curl::curl_fetch_memory(url, handle = h)
      if (r$status_code >= 400) stop("STAC search: HTTP ", r$status_code, ": ", rawToChar(r$content))
      jsonlite::fromJSON(rawToChar(r$content), simplifyVector = FALSE)
    }
    items <- c(items, page$features)
    nxt <- Filter(function(k) identical(k$rel, "next"), page$links)
    if (!length(nxt)) break
    nxt <- nxt[[1]]
    url <- nxt$href
    body <- if (identical(nxt$method, "POST")) {
      if (isTRUE(nxt$merge) && !is.null(body)) utils::modifyList(body, nxt$body) else nxt$body
    } else NULL
  }
  items
}

# Items from a STAC-GeoParquet file through GDAL's Parquet driver (needs libgdal-arrow-parquet),
# filtered like stac_search: collections, a STAC datetime interval (inclusive), and a lon/lat
# geometry (GeoJSON list) or bbox, exact intersection. Assets from the flattened
# "assets.<name>.href" fields; every other field is a property. Items in time order.
items_from_geoparquet <- function(path, collections = NULL, datetime = NULL, intersects = NULL, bbox = NULL) {
  # GDAL's Parquet driver pre-filters on a "bbox" column when there is one, and drops rows whose
  # bbox is null or crosses the antimeridian (xmin > xmax): 6 of 60 matching items in DEA's EW
  # index (GDAL 3.13.3). We filter all rows ourselves, but keep the driver out of it too.
  old <- gdalraster::get_config_option("OGR_PARQUET_USE_BBOX")
  gdalraster::set_config_option("OGR_PARQUET_USE_BBOX", "NO")
  on.exit(gdalraster::set_config_option("OGR_PARQUET_USE_BBOX", old))
  v <- new(gdalraster::GDALVector, if (grepl("^https?://", path)) paste0("/vsicurl/", path) else path)
  d <- v$fetch(-1)
  v$close()
  gcol <- attr(d, "gis")$geom_column
  keep <- rep(TRUE, nrow(d))
  if (!is.null(collections)) keep <- keep & d$collection %in% collections
  if (!is.null(datetime)) {
    iv <- interval(datetime); t <- as.numeric(d$datetime)
    keep <- keep & !is.na(t) & t >= iv[1] & t <= iv[2]
  }
  if (!is.null(bbox)) intersects <- list(type = "Polygon", coordinates = list(list(
    c(bbox[1], bbox[2]), c(bbox[3], bbox[2]), c(bbox[3], bbox[4]), c(bbox[1], bbox[4]), c(bbox[1], bbox[2]))))
  if (!is.null(intersects)) {
    g <- geojson_to_wkb(intersects)
    keep[keep] <- vapply(d[[gcol]][keep], function(x) gdalraster::g_intersects(x, g), NA)
  }
  d <- d[keep, , drop = FALSE]
  env <- gdalraster::g_envelope(d[[gcol]])
  if (is.null(dim(env))) env <- matrix(env, ncol = 4)
  fields <- setdiff(names(d), c("FID", gcol))
  ms <- function(x) {  # POSIXct -> ISO 8601 with milliseconds, rounded (format() truncates)
    m <- round(as.numeric(x) * 1000)
    sprintf("%s.%03dZ", format(as.POSIXct(m %/% 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%dT%H:%M:%S"), m %% 1000)
  }
  items <- lapply(seq_len(nrow(d)), function(r) {
    props <- list(); assets <- list()
    for (k in fields) {
      v <- d[[k]][[r]]
      if (is.null(v) || (length(v) == 1 && is.na(v))) next
      if (inherits(d[[k]], "POSIXct")) v <- ms(d[[k]][r])
      if (inherits(v, "integer64")) v <- as.numeric(v)
      if (startsWith(k, "assets.")) {
        nm <- sub("^assets\\.", "", k); key <- sub(".*\\.", "", nm); nm <- sub("\\.[^.]*$", "", nm)
        assets[[nm]][[key]] <- v
      } else props[[k]] <- v
    }
    id <- props$id; coll <- props$collection; props$id <- NULL; props$collection <- NULL
    list(type = "Feature", id = id, collection = coll, bbox = as.list(env[r, c(1, 3, 2, 4)]),
         properties = props, assets = assets)
  })
  items[order(vapply(items, function(i) as.numeric(item_time(i)), 0))]
}

# A GeoJSON geometry (list) as WKB, read by OGR from a GeoJSON file in /vsimem.
geojson_to_wkb <- function(geom) {
  f <- sprintf("/vsimem/stacgrid_geom_%d_%s.geojson", Sys.getpid(), basename(tempfile("")))
  on.exit(gdalraster::vsi_unlink(f))
  fc <- list(type = "FeatureCollection", features = list(list(type = "Feature", properties = list(), geometry = geom)))
  con <- new(gdalraster::VSIFile, f, "w")
  con$write(charToRaw(as.character(jsonlite::toJSON(fc, auto_unbox = TRUE, digits = NA))))
  con$close()
  v <- new(gdalraster::GDALVector, f)
  on.exit(v$close(), add = TRUE, after = FALSE)
  x <- v$getNextFeature()
  x[[attr(x, "gis")$geom_column]]
}

grid_from_bbox <- function(bbox, crs, res, bbox_crs = "EPSG:4326", densify = 21) {
  b <- gdalraster::transform_bounds(bbox, bbox_crs, crs, densify_pts = densify)
  e <- c(floor(b[1] / res) * res, floor(b[2] / res) * res, ceiling(b[3] / res) * res, ceiling(b[4] / res) * res)
  list(crs = crs, extent = e, res = res,
       width = as.integer(round((e[3] - e[1]) / res)), height = as.integer(round((e[4] - e[2]) / res)))
}

# The grid of an existing north-up raster (as odc's geobox= from a file).
grid_from_raster <- function(path) {
  ds <- new(gdalraster::GDALRaster, path)
  on.exit(ds$close())
  gt <- ds$getGeoTransform(); w <- ds$getRasterXSize(); h <- ds$getRasterYSize()
  if (gt[3] != 0 || gt[5] != 0 || gt[2] != -gt[6]) stop("needs a north-up grid with square pixels")
  list(crs = ds$getProjection(), extent = c(gt[1], gt[4] + h * gt[6], gt[1] + w * gt[2], gt[4]),
       res = gt[2], width = w, height = h)
}

# The grid's outline in `crs` as a GeoJSON Polygon (a list), `densify` points per edge.
grid_footprint <- function(grid, crs = "EPSG:4326", densify = 21) {
  e <- grid$extent; u <- seq(0, 1, length.out = densify); v <- u[-1]
  x <- c(e[1] + (e[3] - e[1]) * u, rep(e[3], length(v)), e[3] - (e[3] - e[1]) * v, rep(e[1], length(v)))
  y <- c(rep(e[4], densify), e[4] - (e[4] - e[2]) * v, rep(e[2], length(v)), e[2] + (e[4] - e[2]) * v)
  p <- gdalraster::transform_xy(cbind(x, y), grid$crs, crs)
  list(type = "Polygon", coordinates = list(lapply(seq_len(nrow(p)), function(i) p[i, 1:2])))
}

grid_lon <- function(grid) {
  e <- grid$extent
  gdalraster::transform_xy(cbind((e[1] + e[3]) / 2, (e[2] + e[4]) / 2), grid$crs, "EPSG:4326")[1, 1]
}

item_time <- function(item) parse_time(item$properties$datetime)

# Solar date: UTC + trunc(lon / 15) whole hours (as odc-stac), at `lon` or the item's bbox centre.
solar_day <- function(item, lon = NULL) {
  if (is.null(lon)) lon <- (item$bbox[[1]] + item$bbox[[3]]) / 2
  format(item_time(item) + trunc(lon / 15) * 3600, "%Y-%m-%d", tz = "UTC")
}

# Group items, (time, id) order within each group, groups in label order. With `grid`, solar days use
# the grid centre's longitude for every item, as odc.stac.load does.
group_items <- function(items, by = "solar_day", grid = NULL) {
  lon <- if (is.null(grid)) NULL else grid_lon(grid)
  key <- if (is.function(by)) by else switch(by,
    solar_day = function(i) solar_day(i, lon),
    time = function(i) i$properties$datetime,
    function(i) as.character(i$properties[[by]]))
  # time then id, as odc-stac: decides which of two items with the same datetime wins a merge.
  # radix = C-locale string order, the same as Python's
  items <- items[order(vapply(items, function(i) as.numeric(item_time(i)), 0),
                       vapply(items, function(i) i$id, ""), method = "radix")]
  k <- vapply(items, key, "")
  g <- split(items, factor(k, levels = unique(k)))
  g[order(names(g), method = "radix")]
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

# An asset's scale and offset from its STAC metadata: raster extension v1 ("raster:bands"[[1]]),
# STAC 1.1 "bands"[[1]] or asset-level "raster:scale"/"raster:offset". c(1, 0) when absent.
scale_offset <- function(item, asset) {
  a <- item$assets[[asset]]
  b <- if (length(a[["raster:bands"]])) a[["raster:bands"]][[1]] else if (length(a$bands)) a$bands[[1]] else list()
  pick <- function(k) {
    for (v in list(b[[k]], b[[paste0("raster:", k)]], a[[paste0("raster:", k)]])) if (!is.null(v)) return(as.numeric(v))
    NULL
  }
  c(if (is.null(sc <- pick("scale"))) 1 else sc, if (is.null(of <- pick("offset"))) 0 else of)
}

# Each asset as an array [x, y, group] (x fastest, rows top-down, as GDAL reads).
# workers: warps run in that many forked processes (parallel::mclapply; serial on Windows).
# Results are merged in item order whatever order they finish in, so pixels don't depend on it.
# scale: FALSE returns the stored values (as odc-stac 0.5). TRUE applies each item's own scale and
# offset (scale_offset()) before merging, NA for nodata, written as Float32: items in one group can
# carry different offsets (Sentinel-2 processing baselines), so scaling after the merge can be
# wrong for part of a group.
stac_load <- function(groups, assets, grid, resampling = "near", overviews = "AUTO", fuse = "first",
                      workers = 8L, scale = FALSE) {
  jobs <- do.call(rbind, lapply(assets, function(asset) do.call(rbind, lapply(seq_along(groups), function(g)
    data.frame(asset = asset, g = g, i = seq_along(groups[[g]]),
               src = vapply(groups[[g]], asset_href, "", asset = asset))))))
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
      sel <- which(jobs$asset == asset & jobs$g == g)
      for (j in sel) {
        w <- res[[j]]
        a <- w$values
        valid <- if (is.na(w$nodata)) !is.na(a) else !is.na(a) & a != w$nodata
        if (scale) {
          so <- scale_offset(groups[[g]][[jobs$i[j]]], asset)
          a <- a * so[1] + so[2]
          a[!valid] <- NA
          w$nodata <- NA_real_; w$type <- "Float32"
        }
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
