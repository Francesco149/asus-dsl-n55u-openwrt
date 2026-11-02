# Repurposing: OpenWrt port (and why not OPNsense)

## OPNsense: not possible

OPNsense supports only x86-64, with a minimum of a 1 GHz dual-core CPU, 3 GB RAM and 4 GB storage
(docs.opnsense.org/manual/hardware.html). This unit is a 500 MHz single-core MIPS32 with 128 MB RAM and 8 MB flash,
and FreeBSD itself dropped MIPS in 14.0. A sensible combination: OPNsense on an x86 mini-PC as the edge router, with this
unit on OpenWrt as an AP / managed switch behind it.

## Why OpenWrt is realistic

- OpenWrt (main and 25.12.6) still builds `ramips/rt3883` with `asus_rt-n56u` (same SoC, same 0x50000/7872k firmware window,
  same bootloader).
- `CONFIG_RTL8367B_PHY=y` is already built into the rt3883 kernel, and that driver supports the RTL8367R-VB.
- Prior art: a forum user booted the RT-N56U image on a DSL-N55U-B. Wi-Fi and LuCI worked, **Ethernet did not**
  (forum.openwrt.org/t/195217). The cause, per the GPL: the RT-N56U DT uses `realtek,rtl8367` (RTL8367M) on SMI GPIO 2/1, while
  this board needs `realtek,rtl8367b` on **GPIO 22/23** with the CPU on EXT1.
- Other options seen: Padavan (RT-N56U), and the Merlin-based "dsl-n55u-bender" fork.

## The port (`openwrt-port/`, applied to `openwrt/` at tag v25.12.6)

`openwrt-port/0001-ramips-add-support-for-ASUS-DSL-N55U.patch`:

1. `target/linux/ramips/dts/rt3662_asus_dsl-n55u.dts`
   - RT-N56U base: CFI flash and partitions (u-boot / nvram / factory / `denx,uimage` firmware), ethernet fixed-link
     1000/full, MAC from factory 0x4, EHCI/OHCI.
   - Switch: `compatible = "realtek,rtl8367b"`, `gpio-sda = <&gpio0 22>`, `gpio-sck = <&gpio0 23>`,
     `realtek,extif = <5 1 2 1 1 1 1 1 1 2>`. Format: `<cpu_port txdelay rxdelay mode force txpause rxpause link duplex speed>`.
     On RTL8367R-VB the driver requires `cpu_port 5`, which it maps to extif1 (`rtl8367b.c:794`). The delays are from ASUS
     (`txDelay_user=1`, `rxDelay_user=2`).
   - Pinmux: `groups = "i2c", "spi", "uartf", "mdio"; function = "gpio"`, the same as stock GPIOMODE 0x189f.
     The ethernet `mdio-bus` is disabled in `rt3883.dtsi`, so there's no conflict.
   - Keys: reset GPIO3, WPS gpio1 2 (=26). LEDs: power GPIO0 (boot/failsafe/running/upgrade), WAN gpio1 1 (=25).
   - Radios: SoC `wmac` = 5 GHz (`ralink,2ghz = <0>`, EEPROM factory 0x0); PCI `pci1814,3091` at `pci1` = 2.4 GHz
     (EEPROM factory 0x8000).
   - Deliberately left out for now: the Wi-Fi slide switch (GPIO1), so rfkill can't toggle the radios at boot; LAN/USB/wifi LEDs.
2. `target/linux/ramips/image/rt3883.mk`: `Device/asus_dsl-n55u`, same recipe as the RT-N56U
   (`sysupgrade_bin | check-size | mkrtn56uimg -s | append-metadata`, `IMAGE_SIZE := 7872k`, `kmod-usb-ohci kmod-usb2`).
3. `target/linux/ramips/rt3883/base-files/etc/board.d/02_network`: `"1:lan" "2:lan" "3:lan" "4:lan" "5@eth0"`.
   **Port 0 (the TC3162 DSL CPU) is kept out of the LAN.** Label MAC = factory 0x4. No WAN by default; configure one later
   (e.g. a VLAN on one LAN port).

`openwrt-port/files/etc/uci-defaults/99-dsl-n55u-bringup` (bring-up only): on first boot it enables all radios with
a WPA2 AP `DSL-N55U-setup` bridged to LAN. This is the way in if the wired switch fails. The PSK is substituted from
`backup/openwrt-fallback-wifi.txt` by `apply.sh`. The country code is unset (world regdomain), so 5 GHz may not start;
2.4 GHz will. The host's `wlo1` can connect.

`openwrt-port/diffconfig`: target ramips/rt3883, device asus_dsl-n55u, `luci`.
The official RT-N56U 25.12.6 image with LuCI is 6,029,587 bytes, so there's ~1.8 MB of headroom in 7872k.

## Build

```sh
openwrt-port/apply.sh                                  # clone v25.12.6 if needed, apply patch + files + .config
podman build -t dsl-n55u-owrt openwrt-build/           # Debian bookworm build env, rootless
openwrt-build/run.sh bash -c './scripts/feeds update -a && ./scripts/feeds install -a && make defconfig'
openwrt-build/run.sh make -j20                         # output: openwrt/bin/targets/ramips/rt3883/
```
The first full build (toolchain + kernel + packages) takes a while. Logs go to `openwrt/build*.log`.

### First build (2026-11-02, ~25 min on 20 cores): OK
`openwrt/bin/targets/ramips/rt3883/openwrt-ramips-rt3883-asus_dsl-n55u-squashfs-sysupgrade.bin`, 5,701,899 bytes.
Verified offline before flashing:
- `uimage_check.py`: magic, header and data CRC OK (`ih_size` 0x1da5df = kernel only), squashfs directly after it at 0x1da61f → ACCEPT.
- The DTB appended to the kernel (lzma payload) is byte-identical to `build_dir/.../image-rt3662_asus_dsl-n55u.dtb`.
  Decompiled: `realtek,rtl8367b`, `gpio-sda = <gpio0 22>`, `gpio-sck = <gpio0 23>`, extif `<5 1 2 1 1 1 1 1 1 2>`,
  reset `<gpio0 3 ACTIVE_LOW>`, WPS `<gpio1 2 ACTIVE_LOW>`, LEDs gpio0 0 / gpio1 1, pinmux groups i2c/spi/uartf/mdio
  (phandle 0x10 = gpio@600 = GPIO0-23, 0x11 = gpio@638 = GPIO24-39).
- Rootfs: `etc/board.d/02_network` has the dsl-n55u case, `etc/uci-defaults/99-dsl-n55u-bringup` has the 16-char PSK,
  and the manifest includes luci, uhttpd, dropbear, swconfig, wpad-basic-mbedtls, kmod-rt2800-pci/soc, kmod-usb2.

## Image format constraints (why the flashing plan is what it is)

- U-Boot boot check = magic + header CRC + data CRC over `ih_size`, nothing else.
- OpenWrt's sysupgrade image (`mkrtn56uimg -s`): `ih_size` = kernel only, squashfs directly after the uImage, with
  padjffs2 `deadc0de` markers. Passes the boot check (the official RT-N56U image does: `scripts/uimage_check.py`).
- OpenWrt's `mtdsplit_uimage` looks for the rootfs **after** `uimage_offset + 64 + ih_size`. A "factory"-style header
  with `ih_size` covering everything would hide the rootfs and the kernel would have no root. That's why OpenWrt no longer
  builds RT-N56U factory images, and why `04_handle_checksumming` (a header-swap preinit hook for RT-N56U) is legacy.
- DSL rescue mode writes only `ih_size + 64` and checks productid `DSL-N55U`, so it **can't install OpenWrt**.
  Rescue is for going back to stock.

## Flashing plan (no UART)

`scripts/flash-openwrt.sh <...asus_dsl-n55u-squashfs-sysupgrade.bin> [--go]`, run against the **stock** firmware
with telnet enabled:
1. Offline check (`uimage_check.py`), strip the fwtool metadata trailer.
2. Serve over HTTP from the host, `wget` into the router's `/tmp`, md5 compare.
3. Warm the page cache with every file of the stock rootfs, so nothing faults in from the flash being overwritten.
4. `--go` only: stock `mtd-write -i /tmp/owrt.bin -d linux`. On Ralink this is a raw writer (`rc/mtd.c:mtd_write_main`):
   no format checks; one MEMERASE of `ROUNDUP(len, 64K)` and one write.
5. Read back `head -c LEN /dev/mtd3ro | md5sum` and compare. Only then reboot (sysrq `b`).

Failure modes:
- Partial or failed write: CRC fails, U-Boot enters rescue automatically → `scripts/rescue-flash.sh`.
- OpenWrt boots but the switch is dead: connect over the `DSL-N55U-setup` Wi-Fi.
- OpenWrt boots with no network at all: force rescue mode by bridging the reset wires at power-on (verified working;
  see [03-bootloader-and-recovery.md](03-bootloader-and-recovery.md)) → `scripts/rescue-flash.sh` → stock. UART is a last resort.

## First flash (2026-11-02): SUCCESS

Flashed with `scripts/flash-openwrt.sh ... --go` from stock telnet: `mtd-write` rc=0, read-back md5
`4c22a76f141eff4172dd371a0ad0da24` = image. The script's backgrounded reboot never fired (BusyBox telnetd kills background
jobs on logout; now fixed to run in the foreground), so a manual `echo b > /proc/sysrq-trigger` rebooted it.
First boot: sysrq 20:18:58 → U-Boot link blip 20:19:16-19 → OpenWrt resets the switch 20:20:09-13 → **SSH + LuCI up at
20:20:29 (~90 s)** over the wired LAN.

Verified on the device (`scripts/owrt.sh`):
- `ubus call system board`: `ASUS DSL-N55U`, `asus,dsl-n55u`, OpenWrt 25.12.6 r33311-981c978eff, kernel 6.12.112.
- Switch: `using GPIO pins 534 (SDA) and 535 (SCK)` (gpiochip0 base 512 → GPIO22/23), `RTL8367R-VB chip found
  (num:6000 ver:1010)`, `cpu_port:5, assigned to extif1`. The "cannot find mdio node phandle" line is the expected fallback
  to GPIO SMI.
- Ports: 0 = up 100M (the TC3162 DSL CPU, correctly excluded), **4 = the host cable on front label "LAN1"**, 5 = CPU
  1000M; VLAN 1 = `1 2 3 4 5t`.
- MTD: `firmware` 0x7b0000 split into `kernel` 0x1da61f / `rootfs` / `rootfs_data` 0x240000 (2.25 MiB jffs2, mounted as overlay).
  `md5sum /dev/mtd4ro` (the U-Boot-checked region) == the image's first 0x1da61f bytes, so the boot-time CRC stays valid.
- LEDs `blue:power`, `blue:wan` + rt2800 phy LEDs; keys `reset` = gpio-515 (GPIO3), `wps` = gpio-538 (GPIO26), both idle-high.
- Radios: phy0 = PCI `rt2800pci` (reports "RT chipset 3071", RF 0008; firmware rt2860.bin 0.40), 2.4 GHz; phy1 =
  `rt2800soc` RT3883 / RF3853, 5 GHz. Both `AP-ENABLED` at 20 dBm after enabling the ifaces.
- **Bug found:** the bring-up uci-defaults only cleared `wifi-device.disabled`. In 24.10+ the default `wifi-iface` sections are
  also `disabled='1'`, so the fallback AP never started. Fixed in `openwrt-port/files` (sets `wifi-iface.disabled='0'`).
- From the host, with **no antennas attached**: the 5 GHz AP (BSSID e0:3f:49:XX:XX:6c, ch 36) was heard at ~45-49 %. The 2.4 GHz
  AP (…:68, ch 1) wasn't heard, though its receive path works (the router's own scan sees neighbouring APs). Re-test with antennas.
- Wi-Fi slide switch: GPIO1 reads 1 ("off") → 0 ("on"). It's not mapped in the DT yet.

Rebuild #2 (same day) with the fixes (LAN labels `4:lan:1 … 1:lan:4`, uci-defaults enabling the wifi-ifaces, DTS notes):
`openwrt-ramips-rt3883-asus_dsl-n55u-squashfs-sysupgrade.bin`, sha256 `f5384952…035eff2f`, `uimage_check` ACCEPT. **Not
flashed yet.** Install it from the running OpenWrt with LuCI → System → Backup / Flash firmware, or `sysupgrade`. The device
already has the uci fixes applied by hand.

### Wi-Fi with antennas fitted, country set (verified)
With the antennas on and `country IT` (`iw reg get` → `country IT: DFS-ETSI`; 5 GHz Tx rose from 20 to 23 dBm), a client scan
shows both APs: 2.4 GHz BSSID `…:68` ch 1 at 89 %, 5 GHz BSSID `…:6c` ch 36 at 40 %, both WPA2. Both radios work.

### SSH key auth and rebuild #3
Ed25519 keys were refused: OpenWrt builds dropbear **without Ed25519 on `small_flash` targets** (rt3883 is one), so the
server only offered an RSA host key and rejected every Ed25519 pubkey. Fix: `CONFIG_DROPBEAR_ED25519=y` in
`openwrt-port/diffconfig`. A temporary RSA key bridged access in the meantime. Also hit: `ssh-copy-id` writes
`/root/.ssh/authorized_keys`, which OpenWrt's dropbear ignores (it reads `/etc/dropbear/authorized_keys`), and Ghostty's ssh
wrapper ate the stdin of a piped `cat keys | ssh` (see the README gotchas).

The bring-up uci-defaults is now **guarded**: it only acts while `wireless.default_radio0.ssid` is still `OpenWrt`. Image
uci-defaults re-run after a settings-preserving sysupgrade and must not reset the user's Wi-Fi.
Rebuild #3: sha256 `65cb3ba4…95df32`, `uimage_check` ACCEPT, dropbear contains `ssh-ed25519`.

**Installed via standard `sysupgrade` (settings kept): verified.** The image was piped to `/tmp` over SSH (OpenWrt has no
sftp-server for modern `scp`), sha256-checked, and `sysupgrade -T` passed (`supported_devices` match). `sysupgrade -l` keep list
included `/etc/dropbear/authorized_keys`, the dropbear host key, `/etc/shadow` and `/etc/config/{wireless,network,system}`.
`sysupgrade -v`: "Commencing upgrade", then `ubus ... Connection failed` (normal, as procd takes over); link drop
after ~2 min (flash written), and SSH was back ~4 min after the start. Afterwards: Ed25519 key login works, and country IT, the
Wi-Fi config, the 8 keys and the root password all survived. The temporary RSA key was then removed (7 Ed25519 keys remain).

## After first boot: things to verify
- `dmesg | grep -i rtl8367`: expect `RTL8367R-VB chip found` and `cpu_port:5, assigned to extif1`.
- `swconfig dev switch0 show`, link on ports 1-4, and the physical LAN label ↔ switch port mapping.
- Both radios: `wifi status`, `iw phy`; set the country code.
- Buttons: `logread -f` while pressing reset/WPS (gpio-button-hotplug); then map the Wi-Fi switch (GPIO1).
- Then: make the bring-up Wi-Fi permanent or remove it, set a root password, decide a WAN port, consider upstreaming the device.
