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

- Arm A with R the way a newcomer gets it (apt r-base, then sf/terra), for the R half of the
  comparison.
- Port a real workload from rasterio to osgeo.gdal and compare it with the R version.
- Run the same arms on Nectar, Setonix and a laptop.
