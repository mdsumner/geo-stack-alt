# geo-stack-alt

Is there a better default geospatial stack than "a venv and `pip install rasterio`"? This repo
tests one candidate against that default, from a clean machine, and keeps the evidence.

**Status (2026-11-10):** early. Two install paths compared on `ubuntu:24.04`; one finding about
GDAL itself. Not yet run on Nectar, Setonix or a laptop.

## The stance (draft)

> Use **GDAL itself** as the processing core, from Python (`osgeo.gdal`) and R (`gdalraster`,
> `vapour`, `wk`, with `ximage` for figures), with **one libgdal** shared by both, installed
> by **pixi** from conda-forge and pinned by `pixi.lock`.

The usual default is the wheel stack: rasterio, geopandas/pyogrio and shapely, each with a
private copy of GDAL/PROJ/GEOS inside its wheel, and, for R, sf or terra built separately. That
default is easy to install. The claim here is that the alternative is just as easy now, and
gives you GDAL's own API, a newer GDAL, more drivers, one version of every library across
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
| Drivers missing (of 21 checked) | Parquet, FlatGeobuf, OpenFileGDB, KEA, PostgreSQL, LIBKML | Parquet only (`libgdal-arrow-parquet`, untested) |
| DEM warp | mean 558.9196 | mean 558.9198, identical across osgeo.gdal, gdalraster, vapour |

Raw logs, timings, lockfiles and probe JSON: [`evidence/`](evidence/).

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

## Guidelines so far

1. **Add `libgdal`, not just `gdal`.** conda-forge `gdal` pulls in only `libgdal-core`: no
   netCDF, HDF5, JP2, KEA, PDF or PostgreSQL. `libgdal` adds those plugins (+300 MB).
   Parquet needs `libgdal-arrow-parquet` as well.
2. **ximage** isn't on conda-forge yet. It is pure R, so `install.packages("ximage")` inside the
   env works with no compiler, but it isn't recorded in `pixi.lock`. A conda-forge recipe would
   fix that.
3. **Record the GDAL version and resampling method in every output** (GeoTIFF tags or a
   sidecar). Results depend on the GDAL version, as the finding above shows.
4. On Ubuntu 24.04, plain `pip` outside a venv is refused (PEP 668), and the bare image has no
   pip at all: arm A has to start with `python3-venv`. (The arm records this, but the step
   needs `python3-pip` to show the PEP 668 message itself; to fix.)

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
bash cleanroom/run.sh warp-versions             # GDAL 3.10-3.13, same warp
```

| Path | What |
|---|---|
| `cleanroom/run.sh` | Runs one arm in a fresh container, keeps logs and timings |
| `cleanroom/arms/*.sh` | One script per install path or experiment |
| `cleanroom/probe/` | The shared probe: `probe_gdal.py`, `probe_rasterio.py`, `probe.R`, `common.py` |
| `cleanroom/experiments/` | Scripts behind the warp finding |
| `evidence/` | Outputs of each run (`.tif` files are not kept in git: re-run to get them) |
| `findings/` | Write-ups |

## Caveats

- Timings come from one host with a very fast network. Treat them as a lower bound.
- One base image so far (ubuntu:24.04, x86_64). No macOS or Windows yet, and no HPC
  (Setonix has no Docker, and its conda/pixi file-count limits are unchecked).
- The probe is one small job. A real workload (the aeo26 Sentinel-2 composite, which already
  has an R twin on gdalraster + ximage) is the next test.

## Next

- A Python-only pixi arm, for a fair size and time comparison with arm A.
- `libgdal-arrow-parquet`, and the STAC-GeoParquet index from ga-sar-ice as a test.
- Arm A with R the way a newcomer gets it (apt r-base, then sf/terra), for the R half of the
  comparison.
- Fix arm A's PEP 668 step.
- Port a real workload from rasterio to osgeo.gdal and compare it with the R version.
- Run the same arms on Nectar, Setonix and a laptop.
