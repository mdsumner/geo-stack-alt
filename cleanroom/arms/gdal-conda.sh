#!/usr/bin/env bash
# gdal-conda (hypertidy/gdal-r-ci, conda/): the same steps as gdal-r-ci.sh, in the conda-forge image.
#   IMAGE=ghcr.io/hypertidy/gdal-conda:latest MOUNT=$PWD/stacgrid:/stacgrid:ro bash cleanroom/run.sh gdal-conda
exec bash /cleanroom/arms/gdal-r-ci.sh
