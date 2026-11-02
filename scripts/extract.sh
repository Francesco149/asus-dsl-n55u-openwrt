#!/usr/bin/env bash
# Unpack a stock DSL-N55U .trx (really a uImage: lzma kernel + squashfs 3.0/lzma + DSL-CPU trailer).
#   nix develop -c scripts/extract.sh <firmware.zip|.trx> <outdir>
# Produces: <outdir>/{image.trx,kernel.lzma,kernel.bin,rootfs.sqsh,rootfs/,trailer.bin,info.txt}
set -euo pipefail
IN=$(realpath "$1"); OUT=$2
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
cd "$OUT"

if [[ $IN == *.zip ]]; then
  mkdir -p zip && bsdtar -xf "$IN" -C zip
  IN=$(find zip -name '*.trx' | head -1)
fi
cp -f "$IN" image.trx

python3 -I - image.trx >info.txt <<'EOF'
import sys, struct
d = open(sys.argv[1], 'rb').read()
size = struct.unpack('>I', d[12:16])[0]
end = 64 + size
sq = d.find(b'hsqs', 64, end)
name = d[32:64]
print(f"file_size={len(d)} uimage_end={end} squashfs_off={sq}")
print(f"uimage_time={struct.unpack('>I', d[8:12])[0]} load=0x{struct.unpack('>I', d[16:20])[0]:08x} ep=0x{struct.unpack('>I', d[20:24])[0]:08x}")
print(f"asus_hdr_version_bytes={name[:4].hex()} productid={name[4:].split(b'\0')[0].decode(errors='replace')}")
EOF
eval "$(head -1 info.txt)"
dd if=image.trx of=kernel.lzma bs=64 skip=1 count=$(( (squashfs_off - 64) / 64 )) status=none
dd if=image.trx of=rootfs.sqsh bs=1 skip="$squashfs_off" count=$(( uimage_end - squashfs_off )) status=none
dd if=image.trx of=trailer.bin bs=1 skip="$uimage_end" status=none
lzma -dc kernel.lzma >kernel.bin 2>/dev/null || true
rm -rf rootfs && sasquatch -no-progress -d rootfs rootfs.sqsh >/dev/null 2>&1 || sasquatch -d rootfs rootfs.sqsh >/dev/null
{
  strings kernel.bin | grep -m1 'Linux version' || true
  strings rootfs/bin/busybox | grep -m1 -E '^BusyBox v' || true
} >>info.txt
cat info.txt
