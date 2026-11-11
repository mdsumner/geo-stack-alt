"""stacgrid: STAC items -> groups -> one grid, with osgeo.gdal, numpy and the standard library.

The small layer that osgeo.gdal lacks for STAC time stacks (what odc.stac.load does), with the
two choices that change pixels made explicit: overview use and merge order. The defaults
reproduce odc-stac's load exactly (overviews on, first valid pixel wins); overviews="NONE"
with fuse="last" reproduces GDAL's STACIT mosaic. stacgrid.R is the same thing in R.

    import stacgrid as sg
    items = sg.stac_search("https://explorer.dev.dea.ga.gov.au/stac", ["ga_s1_nrb_iw_hh_1"],
                           bbox=(73.5, -69.1, 74.0, -68.8), datetime="2021-01-01/2021-03-01")
    grid = sg.grid_from_bbox((73.5, -69.1, 74.0, -68.8), "EPSG:3031", 200)
    groups = sg.group_items(items, "solar_day")
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
    """'2021-01-01/2021-03-01' -> full-day RFC 3339 interval, as pystac-client does."""
    a, _, b = d.partition("/")
    a = a + "T00:00:00Z" if a and "T" not in a else a
    b = b + "T23:59:59Z" if b and "T" not in b else b
    return f"{a}/{b}" if b else a


def stac_search(endpoint: str, collections: list[str], bbox=None, datetime=None, limit=100,
                **params) -> list[dict]:
    """All items of a STAC API GET /search, following "next" links."""
    q = dict(collections=",".join(collections), limit=limit, **params)
    if bbox is not None:
        q["bbox"] = ",".join(str(v) for v in bbox)
    if datetime is not None:
        q["datetime"] = _expand_datetime(datetime)
    url, items = f"{endpoint.rstrip('/')}/search?{urllib.parse.urlencode(q, safe=',:/')}", []
    while url:
        page = json.load(urllib.request.urlopen(url, timeout=120))
        items += page["features"]
        url = next((k["href"] for k in page.get("links", [])
                    if k.get("rel") == "next" and k.get("method", "GET") == "GET"), None)
    return items


def grid_from_bbox(bbox, crs: str, res: float, bbox_crs: str = "EPSG:4326", densify: int = 21) -> dict:
    """The bbox in `crs` (edges densified), snapped outwards to multiples of `res`."""
    ct = osr.CoordinateTransformation(_srs(bbox_crs), _srs(crs))
    xl, yb, xr, yt = ct.TransformBounds(*bbox, densify)
    xl, yb = math.floor(xl / res) * res, math.floor(yb / res) * res
    xr, yt = math.ceil(xr / res) * res, math.ceil(yt / res) * res
    return dict(crs=crs, extent=(xl, yb, xr, yt), res=res,
                width=int(round((xr - xl) / res)), height=int(round((yt - yb) / res)))


def _when(item) -> dt.datetime:
    return dt.datetime.fromisoformat(item["properties"]["datetime"].replace("Z", "+00:00"))


def solar_day(item) -> str:
    """Local solar date at the item's bbox centre: UTC + longitude / 15 hours."""
    lon = (item["bbox"][0] + item["bbox"][2]) / 2
    return (_when(item) + dt.timedelta(hours=lon / 15)).date().isoformat()


def group_items(items: list[dict], by: str | Callable = "solar_day") -> dict[str, list[dict]]:
    """Group items, in time order within each group, groups in label order.
    `by`: "solar_day", "time" (each datetime), a property name, or a function of the item."""
    key = (solar_day if by == "solar_day" else
           (lambda i: i["properties"]["datetime"]) if by == "time" else
           by if callable(by) else (lambda i: str(i["properties"][by])))
    groups: dict[str, list[dict]] = {}
    for it in sorted(items, key=_when):
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


def stac_load(groups: dict[str, list[dict]], assets: list[str], grid: dict, resampling="near",
              overviews="AUTO", fuse="first", workers: int = 8) -> dict[str, np.ndarray]:
    """Each asset as a (group, y, x) array. Within a group the items are warped in time order and
    merged: fuse="first" keeps the first valid pixel (odc-stac), "last" the last (a VRT mosaic).
    overviews: "AUTO" lets the warp read a coarser overview when downsampling (gdalwarp and
    odc-stac default), "NONE" always reads full resolution (as through a STACIT mosaic).
    workers: warps run in that many threads (GDAL releases the GIL; the reads are network-bound).
    Results are merged in item order whatever order they finish in, so pixels don't depend on it."""
    jobs = [(asset, g, asset_href(it, asset)) for asset in assets
            for g, members in enumerate(groups.values()) for it in members]
    warp = lambda job: warp_to_grid(job[2], grid, resampling, overviews)  # noqa: E731
    out, acc = {}, {}
    with ThreadPoolExecutor(max(1, workers)) as ex:
        for (asset, g, _), (a, nd) in zip(jobs, ex.map(warp, jobs) if workers > 1 else map(warp, jobs)):
            valid = np.isfinite(a) if nd is None or math.isnan(nd) else a != nd
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
