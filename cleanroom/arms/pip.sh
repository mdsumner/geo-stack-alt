#!/usr/bin/env bash
# Arm A: the default path. Ubuntu python, a venv, pip install rasterio + geopandas.
# Then: can this newcomer get osgeo.gdal? Try pip, uv, and the classic apt libgdal-dev route.
set -uo pipefail
source /cleanroom/arms/lib.sh
export PIP_DISABLE_PIP_VERSION_CHECK=1 DEBIAN_FRONTEND=noninteractive

# Desktop Ubuntu has python3 but not venv or pip; the bare image has none of them.
step apt bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends python3 python3-venv python3-pip curl ca-certificates'
# Ubuntu 24.04 refuses a system-wide pip install (PEP 668): record that, it is the first wall.
step pip_system python3 -m pip install rasterio
step venv python3 -m venv /work/venv
export PATH=/work/venv/bin:$PATH

step pip_stack pip install rasterio numpy geopandas matplotlib
step sizes_pre bash -c 'echo "env_bytes $(du -sb /work/venv | cut -f1)"; echo "env_files $(find /work/venv -type f | wc -l)"; echo "cache_bytes $(du -sb /root/.cache/pip | cut -f1)"; pip list > /out/pip-list.txt'
step probe_rasterio python /cleanroom/probe/probe_rasterio.py /out/probe_rasterio.json

# --- osgeo.gdal for the newcomer ---------------------------------------------------------
# Is there any binary wheel on PyPI?
step pip_gdal_wheel pip download --only-binary=:all: --no-deps -d /tmp/gdalwheel gdal
# What a newcomer actually types.
step pip_gdal pip install gdal
step uv_install bash -c 'curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh'
step uv_gdal /root/.local/bin/uv pip install --python /work/venv/bin/python gdal

# The classic route: distro libgdal-dev, compilers, and a pinned sdist build against it.
step apt_gdal_dev bash -c 'apt-get install -y -qq --no-install-recommends libgdal-dev g++ python3-dev && gdal-config --version'
step pip_gdal_pinned bash -c 'pip install "gdal==$(gdal-config --version)"'
step probe_gdal_apt python /cleanroom/probe/probe_gdal.py /out/probe_gdal_apt.json
# The usual fix when gdal_array is missing: rebuild with numpy visible at build time.
step pip_gdal_numpy bash -c 'pip install setuptools wheel && pip install --no-build-isolation --no-cache-dir --force-reinstall --no-deps "gdal[numpy]==$(gdal-config --version)"'
step probe_gdal_apt2 python /cleanroom/probe/probe_gdal.py /out/probe_gdal_apt2.json

step sizes_post bash -c 'echo "env_bytes $(du -sb /work/venv | cut -f1)"; echo "env_files $(find /work/venv -type f | wc -l)"; echo "cache_bytes $(du -sb /root/.cache/pip | cut -f1)"'
# (above is measured after the osgeo.gdal attempts too; see sizes_pre for the plain stack)
cat /out/sizes_pre.log
