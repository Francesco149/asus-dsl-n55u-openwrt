#!/usr/bin/env bash
# Run a command on the OpenWrt-flashed DSL-N55U over SSH (lab use: host keys not pinned).
#   scripts/owrt.sh 'cmd ...'        (OWRT_HOST=192.168.1.1)
exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o ConnectTimeout=8 "root@${OWRT_HOST:-192.168.1.1}" "$@"
