#!/usr/bin/env python3
"""Offline re-implementation of the DSL-N55U bootloader's image checks.

  uimage_check.py [--rescue] <image>

Default mode = U-Boot boot-time check_trx(0): uImage magic, header CRC32,
data CRC32 over ih_size. Also reports where a squashfs rootfs follows the
kernel (what OpenWrt's mtdsplit "denx,uimage" parser needs).

--rescue adds the rescue-mode TFTP rules (common/cmd_tftpServer.c):
  * productid at offset 36 must be "DSL-N55U" (Annex A U-Boot)
  * file must be > 0x30000 bytes, otherwise rescue writes it over the
    BOOTLOADER region instead of the firmware partition
  * only ih_size + 64 bytes get written, so ih_size must cover everything
    that has to land in flash
Exit status 0 = acceptable, 1 = rejected.
"""
import struct
import sys
import zlib

FW_PART_SIZE = 0x7B0000  # mtd "linux" / OpenWrt "firmware"


def main():
    args = sys.argv[1:]
    rescue = "--rescue" in args
    args = [a for a in args if a != "--rescue"]
    if len(args) != 1:
        sys.exit(__doc__)
    d = open(args[0], "rb").read()
    ok = True

    def fail(msg):
        nonlocal ok
        ok = False
        print("FAIL:", msg)

    if len(d) < 64:
        fail("shorter than a uImage header")
        sys.exit(1)
    magic, hcrc, ts, size, load, ep, dcrc = struct.unpack(">7I", d[:28])
    os_, arch, typ, comp = d[28:32]
    name = d[32:64]
    hdr = bytearray(d[:64])
    hdr[4:8] = b"\0\0\0\0"
    calc_h = zlib.crc32(hdr) & 0xFFFFFFFF
    print(f"file size      {len(d)} (0x{len(d):x})")
    print(f"magic          0x{magic:08x} {'OK' if magic == 0x27051956 else 'BAD'}")
    print(f"header crc     0x{hcrc:08x} calc 0x{calc_h:08x} {'OK' if calc_h == hcrc else 'BAD'}")
    if magic != 0x27051956:
        fail("bad magic")
    if calc_h != hcrc:
        fail("bad header crc")
    if 64 + size > len(d):
        fail(f"ih_size 0x{size:x} runs past end of file")
    else:
        calc_d = zlib.crc32(d[64:64 + size]) & 0xFFFFFFFF
        print(f"ih_size        0x{size:x}; data crc 0x{dcrc:08x} calc 0x{calc_d:08x} {'OK' if calc_d == dcrc else 'BAD'}")
        if calc_d != dcrc:
            fail("bad data crc")
    print(f"load/entry     0x{load:08x} / 0x{ep:08x}  os={os_} arch={arch} type={typ} comp={comp}")
    print(f"ih_name        {name.hex()}  productid@36={name[4:].split(b'\0')[0]!r}")

    sq = d.find(b"hsqs", 64)
    if sq >= 0:
        major = struct.unpack("<H", d[sq + 28:sq + 30])[0]
        if major == 4:
            sq_used = struct.unpack("<Q", d[sq + 40:sq + 48])[0]
            extra = f", bytes_used 0x{sq_used:x}, ends 0x{sq + sq_used:x}"
        else:
            extra = f" (squashfs v{major}.x)"
        print(f"squashfs       at 0x{sq:x} (uImage end 0x{64 + size:x}){extra}")
        if sq < 64 + size:
            print("               note: squashfs lies inside ih_size (stock-style image)")
    else:
        print("squashfs       not found")
    # rescue writes only ih_size+64 bytes; mtd-write writes the whole file
    written = 64 + size if rescue else len(d)
    if written > FW_PART_SIZE:
        fail(f"{written:#x} bytes to write exceed the firmware partition (0x{FW_PART_SIZE:x})")

    if rescue:
        if name[4:12] != b"DSL-N55U" or name[12:13] not in (b"\0",):
            fail("rescue: productid at offset 36 is not exactly 'DSL-N55U' (Annex A)")
        if len(d) <= 0x30000:
            fail("rescue: file <= 0x30000 bytes would be written to the BOOTLOADER")
        if sq >= 0 and sq >= 64 + size:
            fail("rescue: rootfs lies beyond ih_size; rescue would only write the kernel")

    print("RESULT:", "ACCEPT" if ok else "REJECT")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
