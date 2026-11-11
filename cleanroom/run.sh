#!/usr/bin/env bash
# Run one install "arm" from nothing in a fresh container, and keep the evidence.
#
#   bash cleanroom/run.sh pixi            # arm B
#   IMAGE=ubuntu:22.04 bash cleanroom/run.sh pixi
#   MOUNT=/path/to/project:/proj:ro bash cleanroom/run.sh <arm>   # extra read-only input
#
# The container starts from the bare image every time (--rm, no cache volumes), so timings
# include every download. Evidence lands in evidence/<arm>/<image>_<UTC timestamp>/.
set -euo pipefail
arm=${1:?usage: run.sh <arm>}
image=${IMAGE:-ubuntu:24.04}
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out="$root/evidence/$arm${PIXI_EXTRA:+-${PIXI_EXTRA// /-}}${VARIANT:+-$VARIANT}/${image//[:\/]/-}_$stamp"
mkdir -p "$out"
echo "arm=$arm image=$image -> $out"
docker pull -q "$image" >/dev/null
docker image inspect "$image" --format '{{index .RepoDigests 0}}' > "$out/image-digest.txt"
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e ARM="$arm" -e PIXI_EXTRA="${PIXI_EXTRA:-}" -e PIXI_PKGS="${PIXI_PKGS:-}" -e IMAGE="$image" \
  -v "$here:/cleanroom:ro" -v "$out:/out" ${MOUNT:+-v "$MOUNT"} \
  "$image" bash /cleanroom/arms/"$arm".sh
echo "done: $out"
column -t -s $'\t' "$out/steps.tsv"
