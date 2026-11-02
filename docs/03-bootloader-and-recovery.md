# Bootloader and recovery

Source: the ASUS GPL tarball ships the bootloader source at `src-ra/uboot/sysdeps/DSL-N55U/DSL_N55U_Uboot.tgz`
(extracted to `firmware/uboot-src/Uboot.N56U`). It is the **RT-N56U U-Boot 1.1.3** with `#if DSL_N55U` additions.
The on-device bootloader (`backup/flash/mtd0_Bootloader.bin`) reports `U-Boot 1.1.3 (Nov 1 2011)`, with env
`bootdelay=1 baudrate=57600 ipaddr=192.168.1.1 serverip=192.168.1.11 bootcmd=tftp`.

## Boot flow (`lib_mips/board.c` → `common/cmd_tftpServer.c: do_tftpd`)

1. Serial menu with a **1 s** boot delay (options to TFTP-load/flash the kernel or the bootloader).
2. Default choice '3' → `do_tftpd()`:
   - `asus_gpio_init()`, then `DETECT()` reads the buttons **once**:
     - **RESET (GPIO3) low → rescue mode** (TFTP server on 192.168.1.1, waits forever).
     - else, **WPS (GPIO26) low → erase nvram** (0x30000-0x3FFFF, i.e. factory reset), then continue booting.
   - Else `check_trx(0)` on flash 0x50000: uImage magic, header CRC, data CRC over `ih_size`.
     **No productid or signature check at boot.** If it fails → **rescue mode automatically**.
   - Else `bootm`.
3. The DSL build also runs `rtl8367r_switch_init_pre()` early ("early Realtek giga Mac support").

**No LED feedback:** the LED-blink code in the rescue path is `#if 0`'d out in this build. The "power LED blinks
slowly in rescue mode" behavior in ASUS's generic instructions does **not** happen on this model. You can only
tell rescue mode from the network (answers ARP at 192.168.1.1, no TCP services).

**Timing of the button sample** (relevant because the reset switch on this unit is dead and must be bridged by hand):
boot menu `bootdelay=1` (1 s) → `set_i2c_spi_to_gpio_mode_and_dir()` (`drivers/mysmi.c`: GPIOMODE bits 0/1 = I2C/SPI as GPIO,
GPIO1 + GPIO3 inputs) → `rtl8367r_switch_init_pre()` (`drivers/myrtk.c`; `test_smi_signal_and_wait()` polls switch reg 0x1202
for 0x88a8, **max 100 × 50 ms = 5 s**) → `do_tftpd()` → `asus_gpio_init()` → `DETECT()`. So the single GPIO3 sample happens
roughly **1-8 s after power-on**. A short has to be solid during that window; holding it 15 s from before power-on is ample.
`rtl8367r_switch_init_pre()` also **powers down all four LAN PHYs** ("to force DHCP renew"). They come back via
`rtl8367r_switch_init()` from `rt2880_eth.c` eth init, i.e. when rescue mode or Linux brings up the network. Expect the
host link to drop briefly during every boot.

## Rescue-mode rules (`common/cmd_tftpServer.c`)

For a file received via TFTP `put`:
- If the transfer is ≤ 0x30000 bytes and passes the magic check, it is written to **0x0-0x2FFFF, the bootloader itself**.
  Never send a small file.
- Otherwise `SolveTRX()`: `check_trx(1)` on the RAM buffer (magic + header CRC + data CRC), then (DSL only)
  `check_image_header()`: magic + `strncmp(buf+36, "DSL-N55U", 8)`. The Annex B build checks "DSL-N55U-B".
- Then it erases 0x50000-0x7FFFFF and writes **only `ih_size + 64` bytes** (`count = ntohl(hdr->ih_size)+64`, DSL only).
  Anything beyond `ih_size` (e.g. the DSL trailer, or an OpenWrt rootfs placed after a kernel-only uImage) is dropped.
- The RRQ path also understands ASUS's Firmware Restoration tool magic (`ASUSSPACELINK` + IP), which is not needed with plain TFTP.

Consequences:
- The stock image (ASUS rescue image = 376_2736 uImage without the trailer) is accepted, and a perfect fit.
- An OpenWrt sysupgrade image **cannot** be installed through rescue: wrong productid, and its `ih_size` covers only the
  kernel. Making `ih_size` cover the whole image would hide the rootfs from OpenWrt's `mtdsplit` (see
  [04-openwrt-port.md](04-openwrt-port.md)).

`scripts/uimage_check.py [--rescue] <image>` replays all of these checks offline.

## Recovery procedures

### A. Rescue mode → stock firmware (no UART). **Verified working 2026-11-02.**
1. Host: `enp3s0` at 192.168.1.10/24 **and 192.168.1.11/24** (the script adds .11), then
   `nix develop -c scripts/rescue-flash.sh` (default image: `firmware/x/rescue376A/image.trx`). It validates the image,
   waits until 192.168.1.1 answers ARP **with port 80 closed**, TFTPs the image from fixed source port 41947, and waits for stock.
2. Router: power off → bridge the reset wires (SRW3 is dead on this unit; a working switch would be held) → power on →
   keep bridged ~15 s → release. **No LED feedback.** Total ≈ 4-5 min to a running stock firmware.
   (Or, with a shell: corrupt the uImage header CRC in mtd3, and U-Boot enters rescue on its own; see B.)

### B. Forcing rescue mode from a shell (button-less)
Because a failed `check_trx` drops into rescue automatically, flipping one byte of the uImage header in the `linux`
partition forces rescue on the next boot. This is the same path a failed or partial OpenWrt write takes.
Status: planned as a test if the button cannot be made to work.

### C. Last resort
UART (ttyS1, 57600 8N1) → U-Boot menu → TFTP-load and write. Or reprogram the TSOP-48 NOR with an external programmer
from `backup/flash/full.bin`.

## Stock-firmware button behavior (for reference)

- `rc/watchdog.c`: RESET held ≥ `RESET_WAIT` = **2 s** while running → restore defaults (LED blinks, reboot).
- With `nvram set asus_mfg=1` (RAM only, no commit) the watchdog's `btn_check()` only records presses
  (`btn_rst=1`, `btn_ez=1`, `btn_wifi_sw=1`) and **returns before the reset logic**. That makes it a safe way to test buttons.
  `ATE Get_ResetButtonStatus` just prints `nvram get btn_rst`.
- BusyBox telnetd kills a session's background jobs on logout. Run long loops inside a session that stays open.

## Rescue/button test log (2026-11-02)

| Time (host) | Action | Result |
|---|---|---|
| ~18:01 | Reset held, power-cycled (LED watched for a blink) | Booted normally (uptime 115 s), not rescue |
| ~18:05 | Reset held before power-on, 10-15 s | Booted normally (uptime 87 s), not rescue |
| ~18:10 | Button test in `asus_mfg` mode (logger died with the telnet session) | Inconclusive |
| ~18:10 | Button test repeated with a persistent session: RESET ~3 s, then WPS ~3 s | **WPS seen, RESET never** |

Result of the persistent-session test (router clock): logger up 00:04:08; `PRESS rst=0 wps=1` at 00:04:53-56
(≈4 s of WPS); no `rst=1` at any point until the logger ended at 00:14:28. `asus_mfg` was restored to 0.

**Case opened (same day):** the reset switch `SRW3` has no continuity when pressed (measured directly on its pins), while
the WPS switch does. **The switch is dead.** Workaround: short SRW3's two front pins (tweezers or a jumper) in place of a press.
`scripts/button-test.sh` checks this live and safely (asus_mfg mode); the shorted pins should show up as `reset=1`.
**Do not short them for 2 s or more on stock firmware outside asus_mfg mode: that's a factory reset.**

**Pin-short live test (`scripts/button-test.sh`, ~18:54):** shorting SRW3's two front pins registered as
`PRESS reset=1` (router clock 00:01:03-04), and WPS as `wps=1` (00:01:38-40). **The GPIO3 net is intact; only the switch is dead.**

**Power-on with the pins shorted (~18:56):** booted normally (uptime 54 s at check). It's not a bootloader mismatch: the GPL
tarball's prebuilt `u-boot.srec` differs from `mtd0` in only 10 bytes. Those are the build timestamps (20:49:08 vs 20:48:55),
an 'A'/'B' flag, the productid string (`DSL-N55U-B` vs `DSL-N55U`) and the matching `strncmp` length (`li v1,10` vs
`li v1,8` @0x15bf0). In other words, ASUS's prebuilt file is the Annex B build, and ours is the Annex A build of the same source.
So `DETECT()` on the device reads GPIO3 exactly as in the source. Most likely cause: the short wasn't solid at the sampling
moment (~1-8 s after power-on). Retry with a firmer short (bent paperclip/jumper) applied **before** power and held 15 s.

**Second power-on attempt (~19:00):** booted normally again (uptime 83 s at check). The code review above found no reason the
bootloader would miss a solid short, so the plan is a reliable contact: a replacement right-angle tact switch, or two
flying leads soldered to SRW3's front pads and brought to any momentary button.

**Third attempt (~19:23), wires soldered to SRW3's front pins and held together through power-on:** booted normally
(uptime 48 s at check), settings intact.

**Disassembly of the on-device bootloader** (`r2 -a mips -b 32 -e cfg.bigendian=false -m 0xbc000000`, addresses from the
GPL `System.map`):
- `DETECT` @0xbc017070: `jalr` via GOT[gp+0x704] = 0xbc017008 = `ralink_gpio_read_bit2` with `a0 = 3`. If 0, it prints
  "BTN_RESET pressed" (string +0x4410) and returns 1. Otherwise it reads `0xb0000648 & 4` (GPIO26 = WPS): if 0, it erases nvram.
- `ralink_gpio_ioctl2` @0xbc016d50 reads `0xb0000620` (PIODATA, GPIO0-23) / `0x648` / `0x670` and shifts by the index.
- `asus_gpio_init` @0xbc017228 reads GPIOMODE `0xb0000060`, ORs in `0x1c` (UARTF→GPIO) and writes it back. It does not
  clear the SPI-GPIO bit set earlier by `set_i2c_spi_to_gpio_mode_and_dir()`.
- **So the binary samples GPIO3 exactly as the source says.** Software can't explain the misses.

Remaining hypothesis: **SRW3's other pin is not plain ground.** It may go to a net that Linux drives low but that floats or is
high during early boot. That would explain `reset=1` in Linux but no detection in U-Boot. Next check (power off): continuity
from each SRW3 front pin to a known ground (USB/SMA shell). Then short the GPIO3-side pin **directly to ground** at power-on.

**Fourth attempt (~19:27), soldered wires held together through power-on: RESCUE MODE ENTERED, and the full round-trip worked.**
The ground hypothesis above turned out to be unnecessary; the earlier misses were just an unreliable short.
Timeline (`captures/rescue-attempt4-carrier.txt`, `captures/rescue-attempt4-20261102.pcap` (local only, *.pcap is gitignored)):

| Time | Event |
|---|---|
| 19:27:12 | link down (power off) |
| 19:27:40 | link up: U-Boot rescue mode (no TCP; answers ARP for 192.168.1.1) |
| 19:29:54+ | U-Boot broadcasts `ARP who-has 192.168.1.11 tell 192.168.1.1` every 2 s |
| 19:29:57 | watcher sends `WRQ image.trx`; **no ACK** (U-Boot ACKs to 192.168.1.11, which nobody owned) |
| 19:30:38 | host adds 192.168.1.11; U-Boot now sends `ACK block 0` to **192.168.1.11:41947**, the source port of the *first* WRQ, whose client had already exited (ICMP port unreachable) |
| 19:31:23-27 | `tftp -R 41947:41947 -m binary 192.168.1.1 -c put image.trx`: **Sent 8032573 bytes in 2.1 s** |
| 19:31:27-19:33:15 | U-Boot erases 0x50000-0x7FFFFF and writes (~1 min 50 s), then resets |
| 19:33:40-41 | link up, stock httpd answering (~20 s boot) |

Verified afterwards: `head -c 8032573 /dev/mtd3ro | md5sum` = `e36f5c36f689635fb541d874c303b67f` = the rescue image.
nvram untouched (`x_Setting=1`, `telnetd_enable=1`).

**ASUS U-Boot TFTP-server quirks** (from the capture, matching the source: the WRQ branch of `TftpHandler` never copies the
sender IP into `NetServerIP`, and `src != TftpServerPort` packets are dropped once out of `STATE_RRQ`):
1. ACKs go to the env **`serverip` = 192.168.1.11**, not to the requester. The host must own 192.168.1.11.
2. U-Boot locks onto the **source port of the first WRQ**. All retries must reuse that port (`tftp-hpa -R P:P`).
   If a session got stuck on a wrong port, power-cycle back into rescue to reset it.
`scripts/rescue-flash.sh` now handles both (adds .11, fixed source port 41947).

**Conclusion: SRW3 is dead, but bridging its two front pins (soldered wires) through power-on reliably enters rescue mode.** That points to
hardware: a broken tact switch, a bad joint, or the pinhole not reaching the switch. The earlier "factory reset" most likely
happened via the web UI. Until it's fixed, **rescue mode can only be entered via a failed CRC** (procedure B), and OpenWrt
failsafe would need the WPS button.
