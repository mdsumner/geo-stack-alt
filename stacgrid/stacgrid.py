"""stacgrid: STAC items -> groups -> one grid, with osgeo.gdal, numpy and the standard library.

The small layer that osgeo.gdal lacks for STAC time stacks (what odc.stac.load does), with the
two choices that change pixels made explicit: overview use and merge order. The defaults
reproduce odc-stac's load exactly (overviews on, first valid pixel wins); overviews="NONE"
with fuse="last" reproduces GDAL's STACIT mosaic. stacgrid.R is the same thing in R.

    import stacgrid as sg
    items = sg.stac_search("https://explorer.dev.dea.ga.gov.au/stac", ["ga_s1_nrb_iw_hh_1"],
                           bbox=(73.5, -69.1, 74.0, -68.8), datetime="2021-01-01/2021-03-01")
    grid = sg.grid_from_bbox((73.5, -69.1, 74.0, -68.8), "EPSG:3031", 200)
    groups = sg.group_items(items, "solar_day", grid=grid)
    out = sg.stac_load(groups, ["hh_gamma0"], grid)   # {"hh_gamma0": (time, y, x) array}
"""
from __future__ import annotations

import datetime as dt
import json
import math
import urllib.parse
import urllib.request
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from osgeo import gdal, osr

gdal.UseExceptions()


def _srs(defn: str) -> osr.SpatialReference:
    s = osr.SpatialReference()
    s.SetFromUserInput(defn)
    s.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)  # x/y, lon/lat
    return s


def _expand_datetime(d: str) -> str:
    """'2021-01-01/2021-03-01' -> full-day RFC 3339 interval, as pystac-client does; a date-time
    with no zone is taken as UTC."""
    def one(x, end):
        if not x or x == "..":
            return x
        if "T" not in x:
            return x + ("T23:59:59Z" if end else "T00:00:00Z")
        return x if x.endswith("Z") or "+" in x[10:] or "-" in x[10:] else x + "Z"
    a, _, b = d.partition("/")
    return f"{one(a, False)}/{one(b, True)}" if _ else one(a, False)


def _interval(d: str) -> tuple[dt.datetime, dt.datetime]:
    a, _, b = _expand_datetime(d).partition("/")
    p = lambda x: dt.datetime.fromisoformat(x.replace("Z", "+00:00"))  # noqa: E731
    lo = p(a) if a and a != ".." else dt.datetime.min.replace(tzinfo=dt.timezone.utc)
    hi = p(b) if b and b != ".." else (lo if not _ else dt.datetime.max.replace(tzinfo=dt.timezone.utc))
    return lo, hi


def stac_search(endpoint: str, collections: list[str], bbox=None, datetime=None, limit=100,
                intersects: dict | None = None, **params) -> list[dict]:
    """All items of a STAC API /search, following "next" links. GET, or POST when `intersects`
    (a GeoJSON geometry dict) is given: the API wants that as JSON in a POST body (DEA's
    explorer takes POST without advertising it, as pystac-client finds)."""
    q = dict(collections=list(collections), limit=limit, **params)
    if bbox is not None:
        q["bbox"] = list(bbox)
    if datetime is not None:
        q["datetime"] = _expand_datetime(datetime)
    url = f"{endpoint.rstrip('/')}/search"
    if intersects is None:
        q["collections"] = ",".join(collections)
        if bbox is not None:
            q["bbox"] = ",".join(str(v) for v in bbox)
        url, body = f"{url}?{urllib.parse.urlencode(q, safe=',:/')}", None
    else:
        body = dict(q, intersects=intersects)
    items = []
    while url:
        req = urllib.request.Request(url, headers={"Content-Type": "application/json"},
                                     data=None if body is None else json.dumps(body).encode())
        page = json.load(urllib.request.urlopen(req, timeout=120))
        items += page["features"]
        nxt = next((k for k in page.get("links", []) if k.get("rel") == "next"), None)
        if nxt is None:
            break
        url = nxt["href"]
        if nxt.get("method", "GET") == "POST":
            body = {**body, **nxt.get("body", {})} if nxt.get("merge") and body else nxt.get("body", {})
        else:
            body = None
    return items


def items_from_geoparquet(path: str, collections: list[str] | None = None, datetime: str | None = None,
                          intersects: dict | None = None, bbox=None) -> list[dict]:
    """Items from a STAC-GeoParquet file through GDAL's Parquet driver (needs libgdal-arrow-parquet),
    filtered like stac_search: collections, a STAC datetime interval (inclusive), and a lon/lat
    geometry or bbox (exact intersection). Assets come from the flattened "assets.<name>.href"
    fields; every other field becomes a property. Items are in time order."""
    from osgeo import ogr
    # GDAL's Parquet driver pre-filters on a "bbox" column when there is one, and drops rows whose
    # bbox is null or crosses the antimeridian (xmin > xmax, as STAC allows): 6 of 60 matching
    # items in DEA's EW index (GDAL 3.13.3). Off, so every row gets the exact geometry test.
    old = gdal.GetConfigOption("OGR_PARQUET_USE_BBOX")
    gdal.SetConfigOption("OGR_PARQUET_USE_BBOX", "NO")
    try:
        return _items_from_ogr(path, collections, datetime, intersects, bbox)
    finally:
        gdal.SetConfigOption("OGR_PARQUET_USE_BBOX", old)


def _items_from_ogr(path, collections, datetime, intersects, bbox) -> list[dict]:
    from osgeo import ogr
    ds = ogr.Open(path if "://" not in path else "/vsicurl/" + path)
    lyr = ds.GetLayer(0)
    if bbox is not None:
        intersects = dict(type="Polygon", coordinates=[[(bbox[0], bbox[1]), (bbox[2], bbox[1]),
                          (bbox[2], bbox[3]), (bbox[0], bbox[3]), (bbox[0], bbox[1])]])
    g = ogr.CreateGeometryFromJson(json.dumps(intersects)) if intersects is not None else None
    if g is not None:
        lyr.SetSpatialFilter(g)
    lo, hi = _interval(datetime) if datetime else (None, None)
    defn = lyr.GetLayerDefn()
    names = [defn.GetFieldDefn(i).GetName() for i in range(defn.GetFieldCount())]
    items = []
    for f in lyr:
        geom = f.GetGeometryRef()
        if g is not None and not geom.Intersects(g):
            continue
        props, assets = {}, {}
        for i, k in enumerate(names):
            if not f.IsFieldSetAndNotNull(i):
                continue
            if defn.GetFieldDefn(i).GetType() == ogr.OFTDateTime:
                y, mo, d, h, mi, sec, _tz = f.GetFieldAsDateTime(i)  # seconds as float32: keep ms
                v = (dt.datetime(y, mo, d, h, mi, tzinfo=dt.timezone.utc)
                     + dt.timedelta(milliseconds=round(sec * 1000))).isoformat().replace("+00:00", "Z")
            else:
                v = f.GetField(i)
            if k.startswith("assets."):
                name, _, key = k[7:].rpartition(".")
                assets.setdefault(name, {})[key] = v
            else:
                props[k] = v
        if collections and props.get("collection") not in collections:
            continue
        if lo is not None and not lo <= _when(dict(properties=props)) <= hi:
            continue
        x0, x1, y0, y1 = geom.GetEnvelope()
        items.append(dict(type="Feature", id=props.pop("id"), collection=props.pop("collection", None),
                          bbox=[x0, y0, x1, y1], properties=props, assets=assets))
    return sorted(items, key=_when)


def grid_from_raster(path: str) -> dict:
    """The grid of an existing north-up raster (as odc's geobox= from a file)."""
    ds = gdal.Open(path)
    x0, dx, rx, y1, ry, dy = ds.GetGeoTransform()
    if rx or ry or dx != -dy:
        raise ValueError("needs a north-up grid with square pixels")
    w, h = ds.RasterXSize, ds.RasterYSize
    return dict(crs=ds.GetProjection(), extent=(x0, y1 + h * dy, x0 + w * dx, y1), res=dx, width=w, height=h)


def grid_footprint(grid: dict, crs: str = "EPSG:4326", densify: int = 21) -> dict:
    """The grid's outline in `crs` as a GeoJSON Polygon, `densify` points per edge (for searching)."""
    xl, yb, xr, yt = grid["extent"]
    t = [i / (densify - 1) for i in range(densify)]
    ring = ([(xl + (xr - xl) * u, yt) for u in t] + [(xr, yt - (yt - yb) * u) for u in t[1:]] +
            [(xr - (xr - xl) * u, yb) for u in t[1:]] + [(xl, yb + (yt - yb) * u) for u in t[1:]])
    ct = osr.CoordinateTransformation(_srs(grid["crs"]), _srs(crs))
    return dict(type="Polygon", coordinates=[[list(p[:2]) for p in ct.TransformPoints(ring)]])


def grid_from_bbox(bbox, crs: str, res: float, bbox_crs: str = "EPSG:4326", densify: int = 21) -> dict:
    """The bbox in `crs` (edges densified), snapped outwards to multiples of `res`."""
    ct = osr.CoordinateTransformation(_srs(bbox_crs), _srs(crs))
    xl, yb, xr, yt = ct.TransformBounds(*bbox, densify)
    xl, yb = math.floor(xl / res) * res, math.floor(yb / res) * res
    xr, yt = math.ceil(xr / res) * res, math.ceil(yt / res) * res
    return dict(crs=crs, extent=(xl, yb, xr, yt), res=res,
                width=int(round((xr - xl) / res)), height=int(round((yt - yb) / res)))


def _when(item) -> dt.datetime:
    w = dt.datetime.fromisoformat(item["properties"]["datetime"].replace("Z", "+00:00"))
    return w if w.tzinfo else w.replace(tzinfo=dt.timezone.utc)


def grid_lon(grid: dict) -> float:
    """Longitude of the grid's centre."""
    xl, yb, xr, yt = grid["extent"]
    ct = osr.CoordinateTransformation(_srs(grid["crs"]), _srs("EPSG:4326"))
    return ct.TransformPoint((xl + xr) / 2, (yb + yt) / 2)[0]


def solar_day(item, lon: float | None = None) -> str:
    """Solar date: UTC + int(lon / 15) whole hours (truncated, as odc-stac does), at `lon` or else
    at the item's bbox centre."""
    if lon is None:
        lon = (item["bbox"][0] + item["bbox"][2]) / 2
    return (_when(item) + dt.timedelta(hours=int(lon / 15))).date().isoformat()


def group_items(items: list[dict], by: str | Callable = "solar_day", grid: dict | None = None) -> dict[str, list[dict]]:
    """Group items, in (time, id) order within each group, groups in label order.
    `by`: "solar_day", "time" (each datetime), a property name, or a function of the item.
    With `grid`, solar days use the grid centre's longitude for every item, as odc.stac.load does
    (odc-stac 0.5: one longitude for the whole load, offset truncated to whole hours)."""
    lon = grid_lon(grid) if grid is not None else None
    key = ((lambda i: solar_day(i, lon)) if by == "solar_day" else
           (lambda i: i["properties"]["datetime"]) if by == "time" else
           by if callable(by) else (lambda i: str(i["properties"][by])))
    groups: dict[str, list[dict]] = {}
    # time then id, as odc-stac: decides which of two items with the same datetime wins a merge
    for it in sorted(items, key=lambda i: (_when(i), i["id"])):
        groups.setdefault(key(it), []).append(it)
    return dict(sorted(groups.items()))


def asset_href(item, asset: str) -> str:
    """GDAL path of an asset: s3:// -> /vsis3/, http(s) -> /vsicurl/."""
    h = item["assets"][asset]["href"]
    if h.startswith("s3://"):
        return "/vsis3/" + h[5:]
    return "/vsicurl/" + h if h.startswith(("http://", "https://")) else h


def warp_to_grid(src: str, grid: dict, resampling="near", overviews="AUTO") -> tuple[np.ndarray, float | None]:
    """One source onto the grid. Returns the array and its nodata value."""
    ds = gdal.Warp("", src, format="MEM", dstSRS=grid["crs"], outputBounds=grid["extent"],
                   width=grid["width"], height=grid["height"], resampleAlg=resampling,
                   overviewLevel=overviews)
    band = ds.GetRasterBand(1)
    return band.ReadAsArray(), band.GetNoDataValue()


def scale_offset(item: dict, asset: str) -> tuple[float, float]:
    """An asset's scale and offset from its STAC metadata: raster extension v1 ("raster:bands"[0]),
    STAC 1.1 "bands"[0] or asset-level "raster:scale"/"raster:offset". (1, 0) when absent."""
    a = item["assets"][asset]
    b = (a.get("raster:bands") or a.get("bands") or [{}])[0]
    pick = lambda k: b.get(k, b.get(f"raster:{k}", a.get(f"raster:{k}")))  # noqa: E731
    sc, of = pick("scale"), pick("offset")
    return (1.0 if sc is None else float(sc)), (0.0 if of is None else float(of))


def stac_load(groups: dict[str, list[dict]], assets: list[str], grid: dict, resampling="near",
              overviews="AUTO", fuse="first", workers: int = 8, scale: bool = False) -> dict[str, np.ndarray]:
    """Each asset as a (group, y, x) array. Within a group the items are warped in time order and
    merged: fuse="first" keeps the first valid pixel (odc-stac), "last" the last (a VRT mosaic).
    overviews: "AUTO" lets the warp read a coarser overview when downsampling (gdalwarp and
    odc-stac default), "NONE" always reads full resolution (as through a STACIT mosaic).
    workers: warps run in that many threads (GDAL releases the GIL; the reads are network-bound).
    Results are merged in item order whatever order they finish in, so pixels don't depend on it.
    scale: False returns the stored values (as odc-stac 0.5 does). True applies each item's own
    scale and offset (scale_offset()) before merging, as float32 with NaN for nodata: items in one
    group can carry different offsets (Sentinel-2 processing baselines), so scaling after the
    merge can be wrong for part of a group. Computed in float64, then rounded to float32."""
    jobs = [(asset, g, it) for asset in assets for g, members in enumerate(groups.values()) for it in members]
    warp = lambda job: warp_to_grid(asset_href(job[2], job[0]), grid, resampling, overviews)  # noqa: E731
    out, acc = {}, {}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        for (asset, g, it), (a, nd) in zip(jobs, ex.map(warp, jobs) if workers > 1 else map(warp, jobs)):
            valid = np.isfinite(a) if nd is None or math.isnan(nd) else a != nd
            if scale:
                sc, of = scale_offset(it, asset)
                a = (a.astype("float64") * sc + of).astype("float32")
                a[~valid] = np.nan
                nd = float("nan")
            if (asset, g) not in acc:
                a = a.copy()
                a[~valid] = np.nan if nd is None else nd
                acc[asset, g] = (a, valid.copy())
            else:
                m, mv = acc[asset, g]
                take = valid & ~mv if fuse == "first" else valid
                m[take] = a[take]
                mv |= valid
    for asset in assets:
        out[asset] = np.stack([acc[asset, g][0] for g in range(len(groups))])
    return out
