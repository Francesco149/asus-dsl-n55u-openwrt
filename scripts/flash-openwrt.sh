#!/usr/bin/env bash
# Write an OpenWrt sysupgrade image for asus_dsl-n55u from the STOCK firmware's
# telnet root shell (no UART needed).
#   nix develop -c scripts/flash-openwrt.sh <openwrt-...-asus_dsl-n55u-squashfs-sysupgrade.bin> [--go]
# Without --go it does everything except the actual flash write (dry run).
#
# Recovery if anything goes wrong: a partial write fails U-Boot's CRC check,
# and U-Boot then drops into rescue mode by itself -> scripts/rescue-flash.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=$(realpath "$1"); GO=${2:-}
HOST=${HOST_IP:-192.168.1.10}; ROUTER=192.168.1.1; PORT=8055   # HOST_IP = this machine's address on the router LAN
TN() { python3 -I "$ROOT/scripts/tn.py" -t 600 "$@"; }

echo "== 1. offline checks (U-Boot check_trx + layout)"
python3 -I "$ROOT/scripts/uimage_check.py" "$IMG"

# strip OpenWrt's fwtool metadata trailer (if any) -> raw image for mtd
RAW=$(mktemp -d)/owrt.bin
cp "$IMG" "$RAW"
if command -v fwtool >/dev/null; then fwtool -q -t -i /dev/null "$RAW" || true; fi
LEN=$(stat -c%s "$RAW"); SUM=$(md5sum "$RAW" | cut -d' ' -f1)
echo "raw image: $LEN bytes md5 $SUM"

echo "== 2. serve image over HTTP and fetch it on the router"
( cd "$(dirname "$RAW")" && exec python3 -I -m http.server "$PORT" --bind "$HOST" ) >/dev/null 2>&1 &
HTTP_PID=$!; trap 'kill $HTTP_PID 2>/dev/null || true' EXIT
sleep 1
TN "cd /tmp && rm -f owrt.bin && wget -q -O owrt.bin http://$HOST:$PORT/owrt.bin; ls -l owrt.bin; md5sum owrt.bin; free"
RSUM=$(TN "md5sum /tmp/owrt.bin" | awk '/owrt.bin/{print $1}' | tail -1)
[[ $RSUM == "$SUM" ]] || { echo "md5 mismatch on router ($RSUM)"; exit 1; }
echo "router copy verified ($RSUM)"

echo "== 3. warm page cache with the whole stock rootfs (nothing must fault in from flash mid-write)"
TN "for d in /bin /sbin /usr/bin /usr/sbin /lib /usr/lib /www; do find \$d -type f 2>/dev/null; done | while read f; do cat \"\$f\" >/dev/null 2>&1; done; echo cached; free"

if [[ $GO != --go ]]; then echo "dry run complete; re-run with --go to flash"; exit 0; fi

echo "== 4. FLASH: mtd-write -> mtd3 'linux'"
TN "mtd-write -i /tmp/owrt.bin -d linux; echo rc=\$?"

echo "== 5. read back and compare"
BSUM=$(TN "head -c $LEN /dev/mtd3ro | md5sum" | awk '{print $1}' | tail -1)
echo "flash md5 $BSUM (want $SUM)"
[[ $BSUM == "$SUM" ]] || { echo "VERIFY FAILED - do NOT reboot; investigate (or re-run step 4)"; exit 1; }

echo "== 6. reboot into OpenWrt"
# Must run in the foreground: BusyBox telnetd kills background jobs when the session closes
# (a backgrounded reboot silently never happened on 2026-11-02). The session dies mid-command.
TN -t 10 "sync; echo b > /proc/sysrq-trigger" >/dev/null 2>&1 || true
echo "done. OpenWrt should come up at 192.168.1.1 (ssh root@192.168.1.1, LuCI http://192.168.1.1)."
