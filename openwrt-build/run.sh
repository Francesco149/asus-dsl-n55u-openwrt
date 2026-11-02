#!/usr/bin/env bash
# Run a command inside the OpenWrt build container with the source tree mounted at /src.
#   openwrt-build/run.sh make -j20
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
exec podman run --rm -i --userns=keep-id \
  -v "$ROOT/openwrt:/src:Z" -w /src \
  localhost/dsl-n55u-owrt "$@"
