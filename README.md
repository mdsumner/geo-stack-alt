# geo-stack-alt

Is there a better default geospatial stack than "a venv and `pip install rasterio`"? This repo
tests one candidate against that default, from a clean machine, and keeps the evidence.

**Status (2026-11-11):** install paths compared on `ubuntu:24.04` and `26.04`; four real
projects (Sentinel-1 and Sentinel-2) reproduced exactly on the alternative stack; one helper
(`stacgrid/`, Python and R) for STAC time stacks, which also reproduces GA's fast-ice notebook loads. Not yet run on Nectar, Setonix or a laptop.

## The stance (draft)

> Use **GDAL itself** as the processing core, from Python (`osgeo.gdal`) and R (`gdalraster`,
> `vapour`, `wk`, with `ximage` for figures), with **one libgdal** shared by both, installed
> from **binaries**: by **pixi** from conda-forge and pinned by `pixi.lock`, or, on Ubuntu, all
> from **apt** (`python3-gdal` plus R via r2u).

Tested on real work, not just a probe: four recent projects, all of which rest on the usual
rasterio-level operations (read, reproject onto a grid, rasterize, write COGs, plot). In every
one the alternative gave the **same pixels and the same numbers** as the original, on Ubuntu
24.04's GDAL 3.8.4 (February 2024), and for the STAC load on 3.12.2 too
([below](#real-workloads-four-projects)).
It is equivalent, not magic: a little more boilerplate in places, and two traps to know about.
What it buys is fewer dependencies, one GDAL across both languages, and installs with nothing
to compile and no pip/apt conflicts.

The usual default is the wheel stack: rasterio, geopandas/pyogrio and shapely, each with a
private copy of GDAL/PROJ/GEOS inside its wheel, and, for R, sf or terra built separately. That
default is easy to install. The claim here is that the alternative is just as easy now, and
gives you GDAL's own API, more drivers (and, with pixi, a newer GDAL), one version of every library across
languages, and a lockfile.

This is for anyone starting out, not for experts who can build GDAL themselves. The test is
whether a new user, given one page of instructions, ends up with a stack that works and
gives the same answer every time.

## Evidence so far

Each path ("arm") starts from a bare `ubuntu:24.04` container (no python, no curl) and runs the
same probe: a Copernicus 30 m DEM COG read over HTTPS, warped to a 40 km Australian Albers box
at 40 m (bilinear), plus versions, drivers and the shared libraries loaded in the process.

| | **A: venv + pip** | **B: pixi** |
|---|---|---|
| Install | apt python3-venv; `pip install rasterio numpy geopandas matplotlib` | apt curl; pixi; `pixi add python numpy gdal libgdal r-base r-gdalraster r-vapour r-wk`; ximage from CRAN |
| Wall time (fast link) | ~45 s | ~30 s |
| Disk | 555 MB (Python only) | 1.8 GB (Python **and** R) |
| GDAL | 3.12.2 (rasterio), 3.12.4 (pyogrio) | 3.13.3 |
| libgdal copies in one process | **2**, different versions (also 2 PROJ, 2 GEOS) | **1**, same file for Python and R |
| `osgeo.gdal` | not available: no wheel on PyPI; `pip`/`uv pip install gdal` fail without `gdal-config` | yes, incl. `gdal.Run()` (the new CLI as an API) |
| `osgeo.gdal` the hard way | apt `libgdal-dev g++ python3-dev` (82 s), `pip install gdal==3.8.4`, then a `--no-build-isolation` rebuild to get `gdal_array`: GDAL 3.8.4, no `gdal.Run` | n/a |
| R in the same env | not attempted yet | gdalraster 2.7.0, vapour 0.16.0, wk 0.9.5, ximage 0.1.0 |
| Drivers missing (of 21 checked) | Parquet, FlatGeobuf, OpenFileGDB, KEA, PostgreSQL, LIBKML | Parquet only; none with `libgdal-arrow-parquet` (guideline 6) |
| DEM warp | mean 558.9196 | mean 558.9198, identical across osgeo.gdal, gdalraster, vapour |

Raw logs, timings, lockfiles and probe JSON: [`evidence/`](evidence/).

### Python only, like for like

Same clean image, Python only (`cleanroom/arms/pixi-py.sh`, `VARIANT=` and `PIXI_PKGS=`).
"Install" excludes the apt step, which varied from 16 s to 124 s with mirror load.

| | A: venv + pip | B-py core | B-py | B-py like-for-like |
|---|---|---|---|---|
| Packages | rasterio numpy geopandas matplotlib | python numpy gdal matplotlib-base | + libgdal | + libgdal rasterio geopandas |
| Install | 22 s (venv + pip) | 5 s | 5 s | 7 s |
| Env on disk | 534 MB | 626 MB | 934 MB | 1.19 GB |
| Files in env | 9,296 | 14,147 | 23,173 | 31,657 |
| Env + download cache | 677 MB | 770 MB | 1.21 GB | 1.50 GB |
| GDAL drivers | 147 (rasterio) | 191 | 210 | 210 |
| `osgeo.gdal` | no | yes | yes | yes |
| libgdal copies in one process | 2 (3.12.2, 3.12.4) | 1 | 1 | **1**: rasterio and pyogrio both on 3.13.3 |

What this says:

- On disk, pip is smaller: 534 MB against 626 MB for core GDAL, or 934 MB with every
  plugin. The pixi env has 1.5 to 2.5 times as many files, which matters under HPC file-count
  quotas (to check on Setonix).
- pixi is faster once apt is done, because it downloads prebuilt packages in parallel and
  hardlinks them from its cache.
- **conda-forge also removes the duplicate GDAL for rasterio users.** In the like-for-like
  env, rasterio 1.5.2 and pyogrio load the env's single libgdal 3.13.3. The duplicate is
  caused by wheels, not by rasterio.

### The R side: three default paths against pixi

The newcomer installs `sf terra gdalraster vapour wk ximage jsonlite` on a bare `ubuntu:24.04`
with `install.packages()` (arms `r-source`, `r-p3m`, `r-r2u`). Arm B is the pixi env above.

| | A-R source (CRAN) | A-R P3M binaries | A-R r2u | B pixi |
|---|---|---|---|---|
| Setup | `apt install r-base` (130-254 s, pulls compilers) | same, plus a repo URL and an `HTTPUserAgent` option | r2u script: CRAN apt repo, bspm (59 s) | pixi (shared with Python) |
| First `install.packages()` | 87-253 s; **3 of 7 load**: sf, terra, gdalraster, vapour fail (no system libraries) | **3 of 7 load**: binaries install without error, then won't load (no libgdal etc.) | **7 of 7** in 36 s | 7 of 7 |
| Fix | 8 `-dev` packages (sf README set + ssl/curl/xml2), then 535 s compiling: **6 of 7**. sf still fails: s2 needs Abseil (`libabsl-dev`) or cmake, which the usual list omits | 4 runtime libraries from apt, then 19 s: 7 of 7 | none | none |
| R | 4.3.3 | 4.3.3 | 4.6.2 | 4.5.3 |
| GDAL / PROJ / GEOS | 3.8.4 / 9.4.0 / 3.12.1 (Ubuntu) | same | same | 3.13.3 / 9.9.0 / 3.15.0 |
| One libgdal for every package | yes | yes | yes | yes, **and shared with Python** |
| DEM warp, gdalraster and vapour | 558.9196 | 558.9196 | 558.9196 | 558.9198 |
| DEM warp, `terra::project` | 558.9181 | 558.9181 | 558.9181 | not run |

What this says:

- On Linux, R already has the "one GDAL" property: every package links the system libgdal.
  R's problems are the setup cliff (two of three default paths fail first, silently in P3M's
  case) and the **age** of Ubuntu's GDAL (3.8.4, released February 2024).
- **r2u is the strongest R default on Ubuntu:** one script, then binaries for everything,
  with system libraries pulled in by apt. It's limited to Ubuntu LTS and to the distro's
  GDAL. Add `python3-gdal` and you get the all-apt arm below.
- `terra::project` gives a different answer from `gdal.Warp`, gdalraster and vapour **on the
  same GDAL** (mean 558.9181 against 558.9196; min and max agree). Not yet explained.
- The source path's documented system-requirements list is out of date for sf, because of s2
  and Abseil. A newcomer following it ends up with no sf.

### All binaries from apt: `python3-gdal` plus r2u

Arm `apt-all`: apt's `python3-gdal`, numpy and matplotlib, then R and CRAN packages as `.deb`s
through r2u. Python and R load the distro's one libgdal. Nothing compiles, there's no venv.

| | Ubuntu 24.04 | Ubuntu 26.04 | (B pixi, 26.04, for scale) |
|---|---|---|---|
| GDAL / Python / R | 3.8.4 / 3.12 / 4.6.2 | 3.12.2 / 3.14.4 / 4.6.2 | 3.13.3 / 3.15.2 / 4.5.3 |
| R packages that load | 7 of 7 (via r2u, above) | 7 of 7 | 7 of 7 |
| Time / disk | apt-all not run; apt + r2u + 3 R packages took about 2.2 min (tas-s1-figure) | about 3.3 min, 591 MB in total | 1.8 GB env + 309 MB cache |
| Drivers missing (of 21) | not probed | Parquet, KEA | Parquet |
| DEM warp mean | 558.9196 | 558.9196 | 558.9198 |

The warp mean follows the GDAL version, not the installer: 3.8.4 and 3.12.2 agree, and 3.13
differs (finding below). Old distro GDAL turned out to be fine for the real workloads below;
the one place it fell short is GDAL's STACIT driver, which on 3.8.4 can't read current STAC
items (`proj:code`).

### The two means differ, and that is the point

The 0.0002 gap is not a binding difference. GDAL 3.13 changed bilinear/cubic warping for
downsampling factors below 2 (it no longer widens the kernel); 3.10-3.12 agree with each other
and with rasterio's bundled 3.12. Details and an offline repro:
[`findings/2026-11-10-gdal-3.13-warp.md`](findings/2026-11-10-gdal-3.13-warp.md).

What this shows about the stacks:

- Python and R agreed to the last digit in arm B because they used one libgdal.
- In arm A, which GDAL you have depends on which wheel did the work. When rasterio's wheel moves
  to 3.13, this warp changes on `pip install -U`, without warning.
- `pixi.lock` records the exact libgdal build, and every language in the env uses it.

## Real workloads: four projects

Each project's own rasterio code was ported to `osgeo.gdal` (and its figures redone in R where
noted), then both versions were run in the same clean container against **one** libgdal (apt's
`python3-rasterio` and `python3-gdal` link the same file), so any difference comes from the
code, not from two GDAL builds.

| Project | What it does | Result | Evidence |
|---|---|---|---|
| tasmania-s1-change | Sentinel-1 NRB bursts from S3, boxcar, dB change, per-burst windowed `reproject` (average) into a state mosaic, land mask (rasterize), COG | **Bit-identical**: 7 bursts and 3 mosaics, max diff 0, same masks, same stats. No rasterio or shapely in the port | `evidence/tas-s1-compare/` |
| … its figures, in R | 2×2 change maps and histogram with ximage, gdalraster, base graphics | Same decimated pixels as Python's averaged read; stats equal to float32 rounding; same figure | `evidence/tas-s1-figure/` |
| mi-island-s1-mirounga | Plans to reuse the tasmania per-scene step | Covered by the above | |
| aeo26-workshop | Sentinel-2 composites, fire severity, glider records | Main script was already `osgeo.gdal`. The two presenters' scripts, ported: answer table identical, all 3 example PNGs **byte-identical**. The project no longer needs rasterio | `evidence/aeo26-compare/` |
| … its figures, in R | The 3 example figures (false colour, NDVI change, severity with gliders) with ximage, gdalraster, base graphics | Same printed numbers (reflectance ranges, glider counts, true-north angle); decimated severity pixels identical (0 of 1,000,000 differ); same figures, drawn by a different device | `evidence/aeo26-figure/` |
| ga-sar-ice (GA tutorial) | `odc.stac.load` of 45 IW bursts, solar-day groups, 200 m EPSG:3031 | Plain `osgeo.gdal`: **every pixel equal**, but ~90 lines against ~15. With `stacgrid` (below): ~10 lines in Python or R, every pixel equal | `evidence/ga-sar-ice-compare/`, `evidence/stacgrid/` |
| … GA's fast-ice notebooks | `sentinel_1_load_demo` and `fast_ice_from_stac_xarray`: EW from STAC-GeoParquet, IW from the API (`intersects=`), grouped by time, solar day and relative orbit, 40 m EPSG:3031, up to 150 items | With `stacgrid`, Python and R: same items, grids and groups, **0 of 217 M pixels differ**. On pixi only: Ubuntu's GDAL has no Parquet driver | `evidence/fast-ice/` |

Line counts for the ports: tasmania 415 → 459, check_values 181 → 199, make_examples 267 → 277.
The extra lines are the two helpers rasterio hides: an `osr` point/bounds transform with x/y
axis order, and an OGR rasterize.

### The same ports on pixi

Everything above was repeated in one pixi env on a bare `ubuntu:24.04`: conda-forge GDAL 3.13.3
shared by osgeo.gdal, rasterio 1.5.2, odc-stac 0.5.3 and R (gdalraster 2.7.0, ximage from CRAN),
with Python 3.15, numpy 2.5 and matplotlib 3.11. The originals (rasterio, odc-stac) were installed
in a separate `pixi add`, so the alt stack's own install is the first add. Then the outputs were
set against the apt runs.

| | Within the pixi env (original vs port, or Python vs R) | pixi (GDAL 3.13.3) vs apt (3.8.4) |
|---|---|---|
| tasmania bursts, mosaics | 0 pixels differ | bursts: 0 differ. Mosaics: 1 pixel of 593,064 in one band, by 5.8e-11 |
| tasmania stats, Python vs R | equal to float32 rounding | |
| aeo26 answer table, printed numbers | identical | identical, Python and R |
| aeo26 PNGs | original vs port byte-identical; R severity pixels 0 of 1,000,000 differ | same content; rendering differs (matplotlib 3.6.3 vs 3.11.2 image resampling; R fonts) |
| ga-sar-ice: odc, plain GDAL, stacgrid Python and R | 0 pixels differ | 0 differ, each loader |
| ga-sar-ice: STACIT vs no-overview last-wins warp | 0 differ | 0 differ against apt 26.04 (GDAL 3.12.2); it can't run on 3.8.4 |

Install, from a bare image: apt curl 16-27 s, pixi 2-4 s, the alt stack (`python numpy gdal
libgdal matplotlib-base pillow r-base r-gdalraster r-jsonlite`) 5-6 s, ximage 3 s, the
baseline extras 4 s; 2.2 GB env. These workloads didn't show the version-dependent warp
difference in the finding above (not investigated why). The one mosaic pixel is probably
numpy (1.26 vs 2.5) in the mosaic arithmetic, since every input burst is identical; the PNG
differences are the plotting libraries.
(`evidence/pixi-projects/`, `evidence/cross-stack/`)

### STAC time stacks: odc-stac, STACIT and `stacgrid`

odc-stac does more than read: it searches, snaps a grid, groups by solar day and merges
overlaps. To find out exactly what, the same load was done three ways, and every difference was
traced to two choices:

| Loader | Overviews when downsampling | Overlaps | Equal to |
|---|---|---|---|
| `odc.stac.load()` (0.5.3) | read (`-ovr AUTO`) | first valid pixel wins | per-item `gdal.Warp`, defaults, first-wins: 0 pixels differ (GDAL 3.8.4 and 3.12.2) |
| GDAL STACIT mosaic, warped | not available through the VRT | last valid wins | per-item `gdal.Warp`, `overviewLevel="NONE"`, last-wins: 0 of 226,943 differ |

Nearest-neighbour from 20 m to 200 m: the overview choice changes nearly every value (by up to
10 dB); the merge order only the burst overlaps (about 9% of pixels). STACIT has no time axis,
so each solar day is its own search: it was no shorter than plain `osgeo.gdal` (78 lines
against 92) and slower (about 29 s against 12 s, odc 6 s).

[`stacgrid/`](stacgrid/) is the missing layer, in Python (`osgeo.gdal`, numpy, standard library)
and R (`gdalraster`, `jsonlite`), with the same functions: `stac_search` (GET or POST),
`items_from_geoparquet`, `grid_from_bbox`, `grid_from_raster`, `group_items`, `stac_load`.
Overviews, merge order and the solar-day longitude are arguments. On Ubuntu 24.04 and 26.04
its defaults equal `odc.stac.load()` in every pixel, from both languages, and Python equals R
in STACIT mode too. About 300 lines each. Reads run in parallel (threads in Python, forked
processes in R): with 8 workers the load takes about 3 s in Python and 5-6 s in R, against
odc's 6.4 s and 11-13 s serial, with the same pixels at every worker count
(`evidence/stacgrid-parallel/`).

**Scale and offset.** odc-stac 0.5 ignores `raster:bands` scale/offset and returns stored values.
Applying one offset afterwards is wrong where a group mixes items with different offsets: on
Earth Search Sentinel-2 across the 04.00 baseline change, 6 of 17 solar-day groups did, and 1.6
to 2.3 M of 3.9 M pixels came out 0.1 off. `stac_load(..., scale=True)` scales each item before the
merge, equal in every pixel to a per-item odc reference (`evidence/scale/`).

On GA's fast-ice notebooks it equals the notebooks' odc-stac loads in every pixel too
(details in [`stacgrid/README.md`](stacgrid/README.md)). Getting there exposed odc-stac's
solar-day rule: one longitude for the whole load (the grid centre) and whole hours, which
splits differently from a per-item longitude when passes fall near local midnight (150 items at
167°E: 30 groups against 60).

### Traps met on the way

- **`osgeo.gdal` dataset lifetime.** `gdal.Open(p).GetRasterBand(1).ReadAsArray()` in one line
  fails on GDAL 3.8 (`TypeError ... GDALRasterBandShadow`): the dataset is freed before the band
  is read. Keep the dataset in a variable. (`evidence/aeo26-compare/failed/`)
- **Axis order.** `osr` follows the CRS's axis order (lat/lon for EPSG:4326) unless you set
  `OAMS_TRADITIONAL_GIS_ORDER`, which rasterio does for you.
- **apt plus pip.** A venv over apt's rasterio (`--system-site-packages`) breaks as soon as pip
  installs numpy 2 into it: apt's rasterio was built for numpy 1.26 and won't import. Pin numpy
  to apt's version. (`evidence/ga-sar-ice-compare/failed/`)
- **odc-stac's S3 setup** (`configure_s3_access`) needs `odc-stac[botocore]`.
- **R's PNG device needs a UTF-8 locale.** In a bare container (C locale), `·`, `–` and `→` in
  titles come out as `..`. Set `LANG=C.UTF-8`.
- **pandas 3 and stac-geoparquet 0.8.** `stac_geoparquet.to_item_collection` stringifies only
  `datetime64[ns]` columns; pandas 3 reads DEA's EW index as `datetime64[us, UTC]`, and pystac
  fails on the raw Timestamps (`TypeError: object of type 'Timestamp' has no len()`). fast-ice's
  own lock pairs pandas 3.0.3 with stac-geoparquet 0.8.0 (not run). The reference script casts
  to ns first. stacgrid reads the file with OGR and doesn't meet this.
- **GDAL's Parquet driver pre-filters on a `bbox` column** and drops null and antimeridian
  (xmin > xmax) bboxes: 6 of 60 EW items. `OGR_PARQUET_USE_BBOX=NO` turns it off.
- **DEA's STAC API takes POST without advertising it**, and `intersects` only by POST.
- **fast-ice's GeoParquet URL** (`data.dev.dea.ga.gov.au`) returned 504; the S3 copy has the
  sha256 in fast-ice's registry.
- **S3 listing from containers** timed out once (about 9,800 prefixes from 16 threads). Shared
  code, not a stack difference; the tasmania runs reuse a saved burst index.

## Guidelines so far

1. **Add `libgdal` and `libgdal-arrow-parquet`, not just `gdal`.** conda-forge `gdal` pulls in
   only `libgdal-core`: no netCDF, HDF5, JP2, KEA, PDF, PostgreSQL or Parquet. `libgdal` adds
   all but Parquet, which is a separate package because of Arrow. Sizes are in item 6.
2. **ximage** isn't on conda-forge yet: `r-ximage` is submitted
   ([conda-forge/staged-recipes#35576](https://github.com/conda-forge/staged-recipes/pull/35576)).
   Until it lands, `install.packages("ximage")` inside the env works with no compiler, since it
   is pure R, but isn't recorded in `pixi.lock`. Once it's there, add `r-ximage` and drop the
   CRAN step.
3. **Record the GDAL version and resampling method in every output** (GeoTIFF tags or a
   sidecar). Results depend on the GDAL version, as the finding above shows.
4. On Ubuntu 24.04, `pip install` outside a venv fails with `error: externally-managed-environment`
   (PEP 668), so arm A has to start with `python3-venv`. A desktop install has python3 but
   neither venv nor pip.
5. **Use `matplotlib-base`, not `matplotlib`.** On conda-forge, `matplotlib` pulls in Qt6,
   PySide6, LLVM and Clang (about 150 MB compressed). With it, the Python-only env was 1.7 GB
   and 36k files; without it, 934 MB.
6. **Choosing GDAL plugins** (Python only, matplotlib-base, clean ubuntu:24.04):

   | GDAL packages | Env | Files | Drivers | Missing from the 21 checked |
   |---|---|---|---|---|
   | `gdal` (= libgdal-core) | 626 MB | 14k | 191 | netCDF, HDF5, Parquet, JP2, KEA, PDF, PostgreSQL |
   | `gdal libgdal-netcdf libgdal-hdf5 libgdal-jp2openjpeg libgdal-arrow-parquet` | 845 MB | 18k | 203 | KEA, PDF, PostgreSQL |
   | `gdal libgdal` | 934 MB | 23k | 210 | Parquet |
   | **`gdal libgdal libgdal-arrow-parquet`** | **1.02 GB** | **24k** | **212** | none |
   | (pip: rasterio + geopandas wheels, for scale) | 534 MB | 9k | 147 | Parquet, FlatGeobuf, OpenFileGDB, KEA, PostgreSQL, LIBKML |

   Most of the size is the cloud SDKs (gRPC, Google Cloud, AWS, protobuf). TileDB and Arrow
   both pull them in, so the trimmed set saves only 170 MB. **Default to all plugins**
   (`libgdal libgdal-arrow-parquet`); use the trimmed set when files or space are tight.
   Parquet works for real: GDAL's Parquet driver reads the ga-sar-ice EW STAC-GeoParquet index
   over HTTPS in under a second (190 scenes, 149 fields).
7. **On Ubuntu, apt alone is a complete stack**: `python3-gdal` plus R through r2u, no venv, no
   compiler, one libgdal. Its GDAL is the distro's (3.8.4 on 24.04, 3.12.2 on 26.04), which was
   enough for all four projects. Don't mix in pip over apt's binary packages unless you pin
   numpy to apt's version.
8. **Porting rasterio code to `osgeo.gdal`**: call `gdal.UseExceptions()`; set
   `OAMS_TRADITIONAL_GIS_ORDER` on every `osr.SpatialReference`; keep each dataset in a variable
   while you read it; `gdal.Warp(..., format="MEM", outputBounds=, width=, height=)` is
   `reproject` into a window, `osr.CoordinateTransformation.TransformBounds` is
   `transform_bounds`, `gdal.Translate(format="COG")` is a COG copy.
9. **Say which overview and merge rule a load used.** Nearest-neighbour downsampling from an
   overview and from full resolution give different values; odc-stac and STACIT differ on both.
   `stacgrid` makes both arguments.

A starting `pixi.toml` that matches arm B:

```toml
[workspace]
channels = ["conda-forge"]
platforms = ["linux-64"]

[dependencies]
python = "*"
numpy = "*"
gdal = "*"
libgdal = "*"
libgdal-arrow-parquet = "*"
matplotlib-base = "*"
r-base = "*"
r-gdalraster = "*"
r-vapour = "*"
r-wk = "*"
```

then `pixi run Rscript -e 'install.packages("ximage", repos = "https://cloud.r-project.org")'`.

## Reproduce

Needs Docker. Each run starts a fresh container and writes to
`evidence/<arm>/<image>_<UTC time>/`.

```bash
bash cleanroom/run.sh pip                       # arm A
bash cleanroom/run.sh pixi                      # arm B, gdal only
PIXI_EXTRA=libgdal bash cleanroom/run.sh pixi   # arm B with all plugins
IMAGE=ubuntu:22.04 bash cleanroom/run.sh pixi   # another base image
VARIANT=min bash cleanroom/run.sh pixi-py       # Python only (default packages in the script)
VARIANT=like PIXI_PKGS="python numpy gdal libgdal matplotlib-base rasterio geopandas" \
  bash cleanroom/run.sh pixi-py
bash cleanroom/run.sh r-r2u                     # R via r2u (also r-p3m, r-source)
bash cleanroom/run.sh warp-versions             # GDAL 3.10-3.13, same warp
IMAGE=ubuntu:26.04 bash cleanroom/run.sh apt-all  # python3-gdal + r2u, one apt libgdal
bash cleanroom/run.sh tas-s1-compare            # tasmania-s1-change: rasterio vs osgeo.gdal port
bash cleanroom/run.sh tas-s1-figure             # ... and its figures in R (ximage, gdalraster)
MOUNT=$HOME/Git/aeo26-workshop:/aeo26:ro bash cleanroom/run.sh aeo26-compare
bash cleanroom/run.sh ga-sar-ice-compare        # odc-stac vs osgeo.gdal vs STACIT
MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh stacgrid   # stacgrid.py/.R vs odc-stac
MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh stacgrid-parallel   # 1-16 workers
MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh fast-ice   # GA fast-ice notebook loads (pixi)
MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh scale      # raster:bands scale/offset (pixi)
MOUNT="$HOME/Git/aeo26-workshop:/aeo26:ro $PWD/stacgrid:/stacgrid:ro" \
  bash cleanroom/run.sh pixi-projects           # all four project ports in one pixi env
MOUNT="$PWD/evidence:/ev:ro" PIXI_RUN=pixi-projects/<run> \
  bash cleanroom/run.sh cross-stack             # pixi outputs vs the apt runs
```

`MOUNT=` adds read-only bind mounts (a project checkout, `stacgrid/`, `evidence/`), space-separated.

| Path | What |
|---|---|
| `cleanroom/run.sh` | Runs one arm in a fresh container, keeps logs and timings |
| `cleanroom/arms/*.sh` | One script per install path or experiment |
| `cleanroom/probe/` | The shared probe: `probe_gdal.py`, `probe_rasterio.py`, `probe.R`, `common.py` |
| `cleanroom/experiments/` | Scripts behind the warp finding, and the project ports (`tas-s1/`, `aeo26/`, `ga-sar-ice/`, `stacgrid/`), each beside an unchanged copy of the original; `fast-ice/` has the notebooks' load cells as scripts |
| `stacgrid/` | STAC items → groups → grid, Python and R |
| `evidence/` | Outputs of each run (`.tif` files are not kept in git: re-run to get them) |
| `findings/` | Write-ups |

## Caveats

- Timings come from one host with a very fast network. Treat them as a lower bound.
- Ubuntu only (24.04 and 26.04, x86_64). No macOS or Windows yet, and no HPC (Setonix has no
  Docker, and its conda/pixi file-count limits are unchecked).
- The project runs use subsets (7 of 249 bursts at 80 m inputs; one GA tutorial area), chosen
  to run in minutes. The code paths are the full ones.
- The ports were written by someone who knows GDAL and checked against the originals. A
  newcomer would hit the traps above; the guidelines are there for that.
- The project ports ran on apt (24.04, some on 26.04) and pixi (24.04 host image), all on
  one machine.

## Next

- Explain the `terra::project` difference (same GDAL 3.8.4, different mean).
- `stacgrid`: the fast-ice processing beyond the loads (NormCovar); multi-band assets.
- Run the project ports on Nectar, Setonix and a laptop.
