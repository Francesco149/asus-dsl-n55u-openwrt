#!/usr/bin/env bash
# Run a command inside the OpenWrt build container with the source tree mounted at /src.
#   openwrt-build/run.sh make -j20
#   OWRT_TREE=upstream-openwrt openwrt-build/run.sh make -j20   # another checkout under the repo root
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec podman run --rm -i --userns=keep-id \
  -v "$ROOT/${OWRT_TREE:-openwrt}:/src:Z" -w /src \
  localhost/dsl-n55u-owrt "$@"
