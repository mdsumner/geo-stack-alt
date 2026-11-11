# stacgrid

STAC items → groups → one grid, in Python (`stacgrid.py`: osgeo.gdal, numpy, standard library)
and R (`stacgrid.R`: gdalraster, jsonlite; curl for POST searches). The same functions in both:

| Step | Python | R |
|---|---|---|
| Search a STAC API (GET; POST when `intersects=` is given; follows `next`) | `stac_search()` | `stac_search()` |
| Items from a STAC-GeoParquet file (OGR; needs `libgdal-arrow-parquet`) | `items_from_geoparquet()` | `items_from_geoparquet()` |
| Grid: bbox in the target CRS, snapped out to the resolution | `grid_from_bbox()` | `grid_from_bbox()` |
| Grid: copy an existing raster's (odc's `geobox=`) | `grid_from_raster()` | `grid_from_raster()` |
| A grid's outline in lon/lat, to search with | `grid_footprint()` | `grid_footprint()` |
| Group: `"solar_day"`, `"time"`, a property, or a function | `group_items()` | `group_items()` |
| Warp each group's items onto the grid and merge (in parallel; `scale=` applies each item's scale/offset) | `stac_load()` | `stac_load()` |
| An asset's `raster:bands` scale and offset | `scale_offset()` | `scale_offset()` |

It's the layer osgeo.gdal lacks for STAC time stacks, which odc-stac's `load()` provides. The two
choices that change pixels are arguments, not hidden defaults:

- `overviews="AUTO"` lets each warp read a coarser overview when downsampling (gdalwarp's and
  odc-stac's default); `"NONE"` always reads full resolution, as a STACIT mosaic does.
- `fuse="first"`: in overlaps the first valid pixel in time order wins (odc-stac); `"last"`: the last
  wins (a VRT mosaic, STACIT).
- `scale=False` (default) returns stored values, as odc-stac 0.5 does (it ignores scale and
  offset). `scale=True` applies **each item's own** scale/offset before the merge, float32 with
  NaN for nodata. Scaling after the merge is wrong wherever a group mixes items with different
  offsets: see [scale and offset](#scale-and-offset).
- `group_items(items, "solar_day", grid=grid)`: odc-stac's rule, one longitude for the whole
  load (the grid centre) and a whole-hour offset, `int(lon / 15)`. Without `grid`, each item's
  bbox centre. The two can split differently where passes fall near local midnight (150 IW
  items at 167°E: 30 groups with the grid's longitude, as odc; 60 with per-item fractional hours).

## Checked

GA's tutorial load (`de-sar-sample-data` tutorial_c1/03: IW HH, 45 items, solar day, 200 m
EPSG:3031) on Ubuntu 24.04 (GDAL 3.8.4) and 26.04 (GDAL 3.12.2), one libgdal per run
(`cleanroom/arms/stacgrid.sh`, evidence in `evidence/stacgrid/`):

- Python and R defaults equal `odc.stac.load()` in every pixel of both assets; same items, same grid.
- Python and R equal each other with `overviews="NONE", fuse="last"` too, the STACIT behaviour
  (`evidence/ga-sar-ice-compare/`: that setting matches GDAL's STACIT mosaic in every pixel).

## Parallel reads

`stac_load(..., workers = 8)`: the per-item warps run in threads (Python; GDAL releases the GIL)
or forked processes (R, `parallel::mclapply`; serial on Windows). The merge still goes in item
order, so pixels can't depend on which warp finishes first. `workers = 1` is the serial path.

GA tutorial load, 45 items, Ubuntu 24.04, GDAL 3.8.4, wall time including the search, two passes
(`cleanroom/arms/stacgrid-parallel.sh`, `evidence/stacgrid-parallel/`):

| workers | 1 | 4 | 8 | 16 |
|---|---|---|---|---|
| Python | 11.3, 12.0 s | 3.9, 3.9 s | 2.9, 2.8 s | 2.6, 2.6 s |
| R | 12.6, 12.9 s | 8.3, 8.1 s | 5.3, 5.8 s | 4.4, 4.0 s |

`odc.stac.load()` on the same load: 6.4 s (whole script). Every run, both languages, every
worker count: 0 pixels differ from odc-stac.

GA's fast-ice notebooks (`abradley60/fast-ice` 4694c6c, `cleanroom/arms/fast-ice.sh`, evidence
in `evidence/fast-ice/`, pixi, GDAL 3.13.3), the notebooks' odc-stac calls against stacgrid:

| Notebook load | Items | Grid | Groups | Python, R vs odc-stac |
|---|---|---|---|---|
| `sentinel_1_load_demo`: IW from the API, ±6 days, `intersects=` the sample's footprint | 15 | from the sample GeoTIFF, 1702 × 1627 at 40 m | `sat:relative_orbit`: 2 | 0 of 2.9 M pixels differ |
| same, EW from STAC-GeoParquet, ±1 hour | 1 | same | 1 | 0 of 2.8 M |
| `fast_ice_from_stac_xarray`: EW from STAC-GeoParquet, 2019 | 60 | bbox at 77.6°S, 1683 × 1407 at 40 m | `time`: 60 | 0 of 141.9 M |
| same, IW from the API, `intersects=` the bbox outline | 150 | same | solar day: 30 | 0 of 69.0 M |

Same item IDs, same grid, every case. Wall time for the xarray notebook's loads: odc-stac 68 s,
stacgrid Python 77 s, R 114 s (R includes writing the stacks to GeoTIFF).

What it took:

- **POST.** The API wants `intersects` as JSON in a POST body, and DEA's explorer accepts POST
  without advertising it (pystac-client warns, then posts). GET with `intersects` is a 400.
- **GDAL's Parquet bbox pre-filter.** With a spatial filter, the Parquet driver (3.13.3) filters on
  the file's `bbox` column first and drops rows whose bbox is null or crosses the antimeridian:
  6 of 60 EW items. `items_from_geoparquet` sets `OGR_PARQUET_USE_BBOX=NO` and tests every
  geometry itself. Not in Ubuntu's GDAL (no Parquet driver), so this route needs pixi/conda-forge.
- **odc's solar-day rule** (above).

## Scale and offset

Earth Search `sentinel-2-l2a`, red band, near Hobart (0.05°), December 2021 to February 2022, 10 m
EPSG:32755 (`cleanroom/arms/scale.sh`, `evidence/scale/`). 23 items in 17 solar-day groups.
`raster:bands` scale is 0.0001 throughout; offset is 0 for processing baseline 03.01 and -0.1 from
04.00 (25 January 2022). Late-2021 dates have two items, the original (`_0_`, 03.01, offset 0)
and a reprocessing (`_1_`, 05.00, offset -0.1), with the same or nearly the same datetime: **6 of
the 17 groups mix offsets.**

| | vs stacgrid `scale=True` (Python and R) |
|---|---|
| Reference: odc loads each item alone (`groupby="id"`), scaled with its own metadata, merged first-valid in odc's order | 0 of 3.9 M pixels differ |
| odc `groupby="solar_day"` raw, then offset -0.1 for all | 2.29 M differ, by 0.1 |
| odc raw, then offset 0 for all | 1.60 M differ, by 0.1 |

stacgrid's `scale=False` equals odc's raw load in every pixel, Python and R.

Merge order within a group is **(datetime, id)**, as odc-stac sorts. Two of the duplicate pairs
have identical datetimes, so the id decides: `_0_` (the older processing) wins. Ordering by
search order instead changed 449,890 pixels.

Group order: stacgrid orders groups by label, odc-stac by time. They agree here (solar dates,
EW times, relative orbits 69 and 70 in time order) but needn't for property groups.

Not handled: multi-band assets, items in several CRSs needing a
per-item choice. Group labels are the group key (the solar date),
where odc-stac labels a group with its first item's time.
