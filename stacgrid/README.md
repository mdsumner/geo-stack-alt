# stacgrid

STAC items → groups → one grid, in Python (`stacgrid.py`: osgeo.gdal, numpy, standard library)
and R (`stacgrid.R`: gdalraster, jsonlite). The same functions in both:

| Step | Python | R |
|---|---|---|
| Search a STAC API (GET, follows `next`) | `stac_search()` | `stac_search()` |
| Grid: bbox in the target CRS, snapped out to the resolution | `grid_from_bbox()` | `grid_from_bbox()` |
| Group: `"solar_day"`, `"time"`, a property, or a function | `group_items()` | `group_items()` |
| Warp each group's items onto the grid and merge | `stac_load()` | `stac_load()` |

It's the layer osgeo.gdal lacks for STAC time stacks, which odc-stac's `load()` provides. The two
choices that change pixels are arguments, not hidden defaults:

- `overviews="AUTO"` lets each warp read a coarser overview when downsampling (gdalwarp's and
  odc-stac's default); `"NONE"` always reads full resolution, as a STACIT mosaic does.
- `fuse="first"`: in overlaps the first valid pixel in time order wins (odc-stac); `"last"`: the last
  wins (a VRT mosaic, STACIT).

## Checked

GA's tutorial load (`de-sar-sample-data` tutorial_c1/03: IW HH, 45 items, solar day, 200 m
EPSG:3031) on Ubuntu 24.04 (GDAL 3.8.4) and 26.04 (GDAL 3.12.2), one libgdal per run
(`cleanroom/arms/stacgrid.sh`, evidence in `evidence/stacgrid/`):

- Python and R defaults equal `odc.stac.load()` in every pixel of both assets; same items, same grid.
- Python and R equal each other with `overviews="NONE", fuse="last"` too, the STACIT behaviour
  (`evidence/ga-sar-ice-compare/`: that setting matches GDAL's STACIT mosaic in every pixel).

Not handled: STAC POST-only APIs, `raster:bands` scale/offset, multi-band assets, items in several
CRSs needing a per-item choice, parallel reads. Group labels are the group key (the solar date),
where odc-stac labels a group with its first item's time.
