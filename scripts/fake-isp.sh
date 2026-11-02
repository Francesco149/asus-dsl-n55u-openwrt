#!/usr/bin/env bash
# Pose as the router's upstream ISP on its WAN-side ethernet port.
#   nix develop -c scripts/fake-isp.sh up|down|status
# - hands the router a DHCP lease on an isolated subnet
# - resolves *every* DNS name to us and logs the queries
# - catches plain-HTTP phone-home requests
# - records a full pcap
# Host IP forwarding stays off, so the router never reaches the real internet.
set -euo pipefail

IF=${DSL_LAN_IF:-enp3s0}
NET=${FAKE_ISP_NET:-172.30.55}
ME=$NET.1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/captures
RUN=$ROOT/.run
mkdir -p "$OUT" "$RUN"

DNSMASQ=$(command -v dnsmasq)
TCPDUMP=$(command -v tcpdump)
PY=$(command -v python3)

up() {
  [[ $(sysctl -n net.ipv4.ip_forward) == 0 ]] || { echo "ip_forward is on; refusing (router would reach the internet)"; exit 1; }
  sudo nmcli dev set "$IF" managed no || true
  sudo ip addr replace "$ME/24" dev "$IF"
  sudo ip link set "$IF" up
  ts=$(date +%Y%m%d-%H%M%S)

  sudo "$TCPDUMP" -i "$IF" -U -w "$OUT/wan-$ts.pcap" >/dev/null 2>&1 &
  echo $! >"$RUN/tcpdump.pid"

  sudo "$DNSMASQ" --conf-file=/dev/null --keep-in-foreground --bind-interfaces \
    --interface="$IF" --except-interface=lo --listen-address="$ME" \
    --dhcp-range="$NET.100,$NET.150,12h" --dhcp-option=3,"$ME" --dhcp-option=6,"$ME" \
    --dhcp-option=42,"$ME" --dhcp-leasefile="$RUN/leases" --dhcp-authoritative \
    --no-resolv --no-hosts --address=/#/"$ME" \
    --log-queries=extra --log-dhcp --log-facility="$OUT/dnsmasq-$ts.log" >"$RUN/dnsmasq.out" 2>&1 &
  echo $! >"$RUN/dnsmasq.pid"

  sudo "$PY" -I "$ROOT/scripts/catchall_http.py" "$OUT/http-$ts.jsonl" 80 >"$RUN/http.out" 2>&1 &
  echo $! >"$RUN/http.pid"

  echo "fake ISP up on $IF ($ME); logs in $OUT/*-$ts.*"
}

down() {
  for p in http dnsmasq tcpdump; do
    if [[ -f $RUN/$p.pid ]]; then
      sudo pkill -P "$(cat "$RUN/$p.pid")" 2>/dev/null || true
      sudo kill "$(cat "$RUN/$p.pid")" 2>/dev/null || true
      rm -f "$RUN/$p.pid"
    fi
  done
  sudo ip addr flush dev "$IF"
  sudo nmcli dev set "$IF" managed yes || true
  echo "fake ISP down"
}

status() {
  ip -br addr show "$IF"
  cat "$RUN/leases" 2>/dev/null || echo "(no leases)"
}

"${1:-status}"
