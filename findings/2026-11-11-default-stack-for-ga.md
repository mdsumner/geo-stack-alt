# The default geospatial stack, where it moves under you, and an alternative

*For Michael and GA (DEA Antarctica). Draft, 2026-11-11. Every number below comes from a clean-room
run in this repo; the evidence directory is given each time. A wider version for the general
community can come later.*

## The question

Most new geospatial Python work starts with "make a venv and `pip install rasterio`", and when
it needs STAC time stacks, `odc-stac` and xarray. Is that the best default for SAR and
Sentinel work like GA's, and if not, what is?

The alternative tested here: **GDAL itself as the processing core**, from Python (`osgeo.gdal`)
and R (`gdalraster`, with `ximage` for figures), with **one libgdal** shared by both, installed
from **binaries** and **pinned** (pixi and `pixi.lock` from conda-forge; or, on Ubuntu, all from
apt with r2u). Where the default leans on odc-stac, the alternative uses `stacgrid`: about 300
lines in each language that do the same search, grid, group and merge with `gdal.Warp`.

## The short answer

- **The alternative gives the same pixels.** On four real projects (Tasmania Sentinel-1 change,
  the aeo26 Sentinel-2 workshop, GA's SAR sea-ice tutorial, and GA's fast-ice notebooks
  including NormCovar), the ports reproduced the originals exactly. Where they didn't, the
  difference was traced to a named cause. Python and R agree to the pixel, because they share
  one libgdal.
- **The default's risk is not any one package.** It's that a fresh resolve picks up a new
  combination of versions. The biggest problems found were all interactions between versions,
  each invisible to the tests of the packages involved. fast-ice is the clearest case (below).
- **Several choices that change pixels are hidden defaults** several layers down. The
  alternative's main gain is that they become explicit arguments you can see, check and pin.
- **It costs some boilerplate,** most of which `stacgrid` absorbs, and a few traps that are
  written down.

## The fast-ice story

fast-ice (abradley60/fast-ice 4694c6c) is a well-built project: a pixi workspace, a lockfile,
notebooks that use odc-stac, xarray and Johannes Lohse's `normalized_covariance`. The
NormCovar part of `fast_ice_from_stac_xarray.ipynb` (sections 5-10: dB, 12-day pairs, NormCovar
at three windows, the RGB, a 1/10 resample, the SCAR coastline landmask, the image handed to
SAM) was run three ways (`evidence/normcovar/`):

| The notebook's stack | What happens |
|---|---|
| fast-ice's **lock** (odc-stac 0.5.2, odc-geo 0.5.1, xarray 2026.4.0, rasterio 1.5.0, GDAL 3.12.3) | Runs. The alt-stack port equals it in every product |
| The lock with today's **rasterio 1.5.2 / GDAL 3.13.3** | Runs without error. The resampled landmask is all 1, so **the SAM input is entirely black** |
| **Resolved today** within fast-ice's declared ranges | Fails in section 8: `ValueError: cannot convert float NaN to integer` |

How each one happens:

- **The crash.** odc-stac 0.5.3 began labelling its float32 output `nodata: nan` (0.5.2 set no
  attributes). xarray keeps attributes through `10 * log10(...)`. NormCovar copies them onto its
  uint8 RGB. odc-geo then can't make a uint8 fill value out of NaN. Four packages, each doing
  something reasonable.
- **The black image.** Resampling a uint8 array with `dst_nodata=None`, odc-geo still passes its
  fill value 0 to rasterio as the destination nodata. rasterio 1.5.0 didn't hand it on to the
  warp; 1.5.1 does. Since 3.11, GDAL's warper rewrites any valid pixel equal to the destination
  nodata to the next value, so that it isn't read as nodata, and says so in a warning. Every 0
  in the 0/1 landmask becomes 1, and masking with it blanks the image. It doesn't fail: it
  silently feeds SAM a black image.

The lockfile protected fast-ice. Anyone who installs it from its `pyproject.toml` ranges, or
upgrades one package, meets one of the other two rows. The port (stacgrid for the load, numpy and
scipy for the arithmetic, `gdal.Warp` and `gdal.Rasterize` for the two geo steps) doesn't touch
either path, and it matched the locked notebook in every product: the loads, all three
NormCovar windows, the RGB, the resample, the landmask and the SAM input. The R port matched it
apart from float32 against double rounding (51 of 7.1 M RGB values differ by 1), and draws the
figure with ximage.

## The same pattern elsewhere

None of these is a bug in one package. Each one needed the combination to show up.

| What | Combination | Effect | Evidence |
|---|---|---|---|
| Section 8 crash | odc-stac 0.5.3 attrs + xarray keep_attrs + odc-geo fill value | Notebook fails | `evidence/normcovar/` |
| Black SAM input | odc-geo fill value as nodata + rasterio ≥ 1.5.1 + GDAL ≥ 3.11 nodata avoidance | Wrong output, no error | same |
| pandas 3 | pandas 3 reads `datetime64[us]`; stac-geoparquet 0.8 only converts `[ns]` | `to_item_collection` fails (`TypeError`) | `evidence/fast-ice/` |
| GeoParquet bbox | GDAL 3.13 Parquet driver pre-filters on a `bbox` column, drops null and antimeridian bboxes | 6 of 60 EW items returned, no warning | same |
| STACIT on old GDAL | DEA items carry `proj:code` only; GDAL 3.8.4 apparently needs `proj:epsg` (inferred, not bisected) | Ubuntu 24.04's GDAL can't mosaic DEA S1 ("No compatible asset found"); 3.12.2 can | `evidence/ga-sar-ice-compare/` |
| Warp kernel | GDAL 3.13 stopped widening bilinear/cubic for downsampling < 2x | Same command, different DEM values on upgrade (up to 10.9 m) | `findings/2026-11-10-gdal-3.13-warp.md` |
| Rasterize nodata | `gdal_rasterize` since 3.10 sets NoData = 0 on outputs it creates | A 0/1 mask's water becomes nodata | `evidence/normcovar/` |
| Two GDALs in one process | rasterio and pyogrio wheels each bundle their own | 3.12.2 and 3.12.4 in one Python session | `evidence/` (arm A) |

The pip/wheel default makes this worse in one specific way. Which GDAL you get depends on which
wheel did the work, and it moves on `pip install -U` without telling you. The two GDAL findings
are recorded for upstream in `~/Git/osgeo-upstream`.

## Hidden choices that change pixels

Tracing odc-stac's output to the pixel (it can be reproduced exactly) turned up the choices it
makes for you. None is wrong; they just aren't visible at the call site.

| Choice | odc-stac / odc-geo | GDAL's own default | Effect when it differs |
|---|---|---|---|
| Overviews when downsampling | read (`-ovr AUTO`) | same in gdalwarp; never through a STACIT VRT | Nearly every value at 20 m → 200 m, by up to 10 dB |
| Overlap merge | first valid wins, in (time, id) order | last wins in a VRT mosaic | Burst overlaps, about 9% of pixels; 449,890 S2 pixels depend on the id tie-break |
| Solar day | one longitude for the whole load (grid centre), whole hours | n/a | 150 IW items at 167°E: 30 groups, against 60 per item |
| Scale/offset | ignored (raw values) | n/a | S2 across baseline 04.00: 6 of 17 groups mix offsets; one offset after the merge is wrong in 1.6-2.3 M of 3.9 M pixels |
| Resample kernel | always `XSCALE=1 YSCALE=1` | widen with the scale | A "bilinear zoom /10" is 2x2 interpolation, not an area average |
| Integer resample nodata | fill value passed as nodata | none | The black SAM input above (rasterio ≥ 1.5.1) |
| Multi-band assets | bands counted from `raster:bands` only | the file's bands | Earth Search's 3-band TCI loads as one float32 band; `visual.2` is a KeyError |

In `stacgrid` each of these is an argument (`overviews=`, `fuse=`, `grid=` for the solar-day
longitude, `scale=`, `"asset.N"`), with odc-stac's behaviour as the default. That's why its
outputs can be checked against odc-stac pixel for pixel, and why a choice can be changed on
purpose.

## What the alternative costs

- **Boilerplate.** Plain `osgeo.gdal` took about 90 lines against odc-stac's 15 for GA's
  tutorial load. `stacgrid` brings that back to about 10. The other ports grew by 5-10%, mostly
  an `osr` transform with explicit axis order and an OGR rasterize.
- **Traps.** `osgeo.gdal` dataset lifetime (keep the dataset in a variable), axis order
  (`OAMS_TRADITIONAL_GIS_ORDER`), and on conda-forge, install `libgdal` and
  `libgdal-arrow-parquet` as well as `gdal`, or you get a GDAL without netCDF, HDF5 or Parquet.
- **Disk and files.** The pixi env is bigger than the pip wheels (934 MB to 1 GB for Python,
  1.8-2.2 GB with R) and has 1.5 to 2.5 times as many files. That matters under HPC file-count
  quotas, which aren't checked on Setonix yet.
- **What it doesn't replace.** odc-stac and xarray give lazy, chunked (dask) loads and the xarray
  ecosystem. stacgrid loads eagerly into numpy and is meant for the area and time ranges GA's
  notebooks use. For continent-scale lazy cubes, odc-stac remains the tool. The finding is
  about pinning and explicit choices, not about avoiding it.

## Speed

On the GA tutorial load, stacgrid with 8 workers took about 3 s in Python and 5-6 s in R, against
odc-stac's 6.4 s, with the same pixels at every worker count. On the full fast-ice loads (217 M
pixels): odc 68 s, stacgrid Python 77 s, R 114 s. The NormCovar port loads only the two images of
a pair, 4-7 s from a cold start.

## What this suggests for GA

1. **Treat the lockfile as part of the result.** fast-ice's lock was the only one of three
   installs that produced the right answer. Install with `pixi install --locked`, and pin ranges
   in `pyproject.toml` that are known to work, not just `<0.6`.
2. **One libgdal per environment.** On conda-forge, rasterio, pyogrio, osgeo.gdal and R all
   share it. That rules out "which GDAL did this?" between steps and languages.
3. **Make the pixel-changing choices explicit at the call site:** overviews, merge order,
   solar-day rule, scale/offset, resample kernel and nodata. Whichever loader you use, write
   them down.
4. **Keep a pinned reference run and compare to it** when upgrading. Every finding here came from
   comparing two runs that should have agreed.
5. **Consider `osgeo.gdal` (and gdalraster in R) for the core raster steps,** with `stacgrid` or
   similar for STAC loads. Not because the default is wrong, but because there are fewer layers
   between you and the pixels, and so fewer places for a version to move them.
6. **R is a first-class route to the same pixels.** gdalraster plus ximage reproduced the figures
   and arrays, on the same libgdal, with no compilation.

## Limits

- One host, Ubuntu 24.04 and 26.04, x86_64, fast network. Not yet macOS, Windows, Nectar or
  Setonix.
- Subsets of each project, chosen to run in minutes; the code paths are the full ones.
- SAM and SVM in fast-ice were not run (they need torch). The port stops at the SAM input.
- The ports were written by someone who knows GDAL well. A newcomer would need the guidelines
  in the README.

## Where to look

- `README.md`: install paths, project ports, guidelines, reproduce commands.
- `stacgrid/README.md`: what stacgrid does and each check against odc-stac.
- `evidence/<arm>/<image>_<time>/`: logs, `steps.tsv`, lockfiles and comparison JSON for every
  run, each re-runnable with `bash cleanroom/run.sh <arm>`.
- `~/Git/osgeo-upstream/notes/2026-11-11-rasterize-nodata-warp-avoidnodata.md` and
  `2026-11-10-warp-4sample-threshold.md`: the GDAL-side findings, with offline repros.
