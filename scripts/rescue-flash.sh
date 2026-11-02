#!/usr/bin/env bash
# Push a STOCK firmware image to the DSL-N55U bootloader's rescue TFTP server.
#   nix develop -c scripts/rescue-flash.sh [image.trx]     (WAIT=seconds, default 1800)
#
# Enter rescue mode: power off, short RESET (on this unit SRW3 is dead: bridge its two front
# pins / the soldered wires), power on, keep it shorted ~15 s. There is NO LED indication.
# U-Boot also falls into rescue by itself if the flashed image fails its CRC check.
#
# Two quirks of ASUS's U-Boot TFTP server (verified 2026-11-02, see docs/03-bootloader-and-recovery.md):
#  1. It sends its ACKs to the env `serverip` (192.168.1.11), not to the sender's IP.
#     -> the host must own 192.168.1.11 as well.
#  2. It locks onto the UDP source port of the FIRST write request it sees and ignores
#     requests from any other port afterwards. -> every attempt uses the same source port.
#
# Default image = ASUS's official rescue image for 3.0.0.4.376_2736 (Annex A), which
# is byte-identical to the regular firmware's uImage minus the DSL trailer.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMG=$(realpath "${1:-$ROOT/firmware/x/rescue376A/image.trx}")
IF=${DSL_LAN_IF:-enp3s0}
ROUTER=192.168.1.1
SERVERIP=192.168.1.11            # U-Boot env serverip
SPORT=${SPORT:-41947}            # fixed TFTP source port for all attempts
WAIT=${WAIT:-1800}

python3 -I "$ROOT/scripts/uimage_check.py" --rescue "$IMG" || { echo "refusing: image would not be accepted (or is dangerous) in rescue mode"; exit 1; }

# tftp-hpa client (inetutils also ships a 'tftp'; we need tftp-hpa for -R)
TFTP=""
IFS=: read -ra P <<<"$PATH"
for d in "${P[@]}"; do [[ $d == *tftp-hpa* && -x $d/tftp ]] && TFTP=$d/tftp && break; done
[[ -n $TFTP ]] || { echo "tftp-hpa not found in PATH (run inside nix develop)"; exit 1; }

ip -br addr show "$IF" | grep -q '192\.168\.1\.' || { echo "$IF has no 192.168.1.x address"; exit 1; }
ip -br addr show "$IF" | grep -q "$SERVERIP/" || { echo "adding $SERVERIP to $IF (U-Boot replies to serverip)"; sudo ip addr add "$SERVERIP/24" dev "$IF"; }

echo "$(date +%T) waiting up to ${WAIT}s for the bootloader in rescue mode at $ROUTER ..."
end=$((SECONDS + WAIT))
while ((SECONDS < end)); do
  # rescue mode = answers ARP but no TCP services (stock Linux would answer on :80).
  # (It also ARPs "who-has 192.168.1.11 tell 192.168.1.1" every 2 s while waiting.)
  if sudo "$(command -v arp-scan)" -q -I "$IF" "$ROUTER" 2>/dev/null | grep -q "^$ROUTER" &&
     ! nc -z -w1 "$ROUTER" 80 2>/dev/null; then
    echo "$(date +%T) rescue mode detected; uploading from port $SPORT"
    out=$(cd "$(dirname "$IMG")" && timeout 300 "$TFTP" -v -R "$SPORT:$SPORT" -m binary "$ROUTER" -c put "$(basename "$IMG")" "$(basename "$IMG")" 2>&1 || true)
    echo "$out" | tail -2
    if grep -q '^Sent ' <<<"$out"; then
      echo "$(date +%T) upload accepted; U-Boot is erasing/writing flash (~2 min) and will reboot."
      for _ in $(seq 300); do nc -z -w1 "$ROUTER" 80 2>/dev/null && { echo "$(date +%T) stock firmware is back up (http answering)"; exit 0; }; sleep 1; done
      echo "$(date +%T) upload done but the router did not come back on :80 within 5 min"; exit 2
    fi
  fi
  sleep 1
done
echo "$(date +%T) timed out waiting for rescue mode"; exit 1
