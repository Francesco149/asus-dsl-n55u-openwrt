#!/usr/bin/env bash
# Recreate the DSL-N55U OpenWrt build tree from scratch.
#   openwrt-port/apply.sh            # clones OpenWrt (tag in BASE) into ./openwrt if missing
# Then build with:
#   podman build -t dsl-n55u-owrt openwrt-build/
#   openwrt-build/run.sh bash -c './scripts/feeds update -a && ./scripts/feeds install -a && make defconfig && make -j$(nproc)'
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=$ROOT/openwrt-port
TREE=$ROOT/openwrt
TAG=$(grep -o 'tag: v[0-9.]*' "$PORT/BASE" | cut -d' ' -f2)

if [[ ! -d $TREE/.git ]]; then
  git clone --depth 1 --branch "$TAG" https://github.com/openwrt/openwrt.git "$TREE"
fi

cd "$TREE"
if git apply --check "$PORT/0001-ramips-add-support-for-ASUS-DSL-N55U.patch" 2>/dev/null; then
  git apply "$PORT/0001-ramips-add-support-for-ASUS-DSL-N55U.patch"
  echo "patch applied"
else
  echo "patch already applied (or does not apply cleanly) - check 'git -C openwrt status'"
fi

# first-boot fallback Wi-Fi; PSK kept outside git in backup/openwrt-fallback-wifi.txt
PSKFILE=$ROOT/backup/openwrt-fallback-wifi.txt
if [[ ! -s $PSKFILE ]]; then
  mkdir -p "$ROOT/backup"
  psk=$(python3 -I -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(16)))')
  printf 'SSID: DSL-N55U-setup\nWPA2-PSK: %s\n' "$psk" >"$PSKFILE"; chmod 600 "$PSKFILE"
fi
psk=$(awk '/WPA2-PSK/{print $2}' "$PSKFILE")
mkdir -p files/etc/uci-defaults
country=${WIFI_COUNTRY:-}   # e.g. WIFI_COUNTRY=IT openwrt-port/apply.sh
sed -e "s/__FALLBACK_PSK__/$psk/" -e "s/__WIFI_COUNTRY__/$country/g" \
  "$PORT/files/etc/uci-defaults/99-dsl-n55u-bringup" >files/etc/uci-defaults/99-dsl-n55u-bringup
chmod 755 files/etc/uci-defaults/99-dsl-n55u-bringup

cp "$PORT/diffconfig" .config
echo "tree ready: $TREE (.config seeded from diffconfig; run feeds + make defconfig in the container)"
