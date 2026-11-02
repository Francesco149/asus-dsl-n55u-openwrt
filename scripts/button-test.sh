#!/usr/bin/env bash
# Live button test on STOCK firmware, safe against the 2-second reset-to-defaults:
# puts the router in ASUS manufacturing mode (asus_mfg=1, RAM only), in which the
# watchdog only records presses (btn_rst / btn_ez / btn_wifi_sw) and skips its reset logic.
#   scripts/button-test.sh [seconds]      (default 300)
# Prints a line per sampled press, live. asus_mfg is restored to 0 at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SECS=${1:-300}
echo "$(date +%T) waiting for the router's telnet..."
until timeout 2 bash -c 'echo > /dev/tcp/192.168.1.1/23' 2>/dev/null; do sleep 2; done
exec python3 -I "$ROOT/scripts/tn.py" -s -t $((SECS + 60)) \
  "nvram set asus_mfg=1; nvram set btn_rst=0; nvram set btn_ez=0; nvram set btn_wifi_sw=0; echo \"armed \$(date +%T) for ${SECS}s\"; i=0; while [ \$i -lt $SECS ]; do r=\$(nvram get btn_rst); e=\$(nvram get btn_ez); w=\$(nvram get btn_wifi_sw); if [ \"\$r\" = 1 ] || [ \"\$e\" = 1 ] || [ \"\$w\" = 1 ]; then echo \"\$(date +%T) PRESS reset=\$r wps=\$e wifi_sw=\$w\"; nvram set btn_rst=0; nvram set btn_ez=0; nvram set btn_wifi_sw=0; fi; sleep 1; i=\$((i+1)); done; nvram set asus_mfg=0; echo \"disarmed \$(date +%T)\""
