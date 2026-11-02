# ASUS DSL-N55U: OpenWrt port, recovery, and stock-firmware security teardown

The ASUS DSL-N55U is an end-of-life ADSL2+ modem/router (2012). ASUS no longer updates it, and its last firmware ships a
2007 Linux kernel. This repository turns the original hardware revision into an **OpenWrt 25.12** device, documents how to
get there **without a serial console**, how to get back to stock, and what is wrong with the stock firmware.

Everything here was done on one physical unit in November 2026, and every claim is backed by source code, disassembly or
an observation on that unit (see `docs/`). The logs and captures have device identifiers (MACs, UUIDs) redacted.

> **Status:** OpenWrt runs. Wired LAN (switch), persistent overlay, LEDs, buttons, and **both Wi-Fi bands** (2.4 GHz and
> 5 GHz APs seen by a client) are verified on hardware.
> DSL does **not** work under OpenWrt (the DSL modem is a separate TrendChip SoC). Use the unit as an AP / switch / small router.

---

## 1. Does this apply to my unit?

| Revision | Hardware | Stock firmware | This repo |
|---|---|---|---|
| **A1** (Annex A, productid `DSL-N55U`) | Ralink RT3662F + TrendChip TC3162LE, 128 MB RAM, 8 MB NOR | 3.0.0.4.x / 9.0.0.4.380 | **yes** (tested) |
| **B1** (Annex B, `DSL-N55U-B`) | same | same | should work; rescue mode wants Annex B stock images; untested |
| C1, D1 | MediaTek MT7620A / RT63365 | 1.1.x | **no**: completely different platform |

Check the label on the bottom, or the firmware version in the web UI (3.0.0.4.x / 9.0.0.4.x = original hardware).
The board is an **ASUS RT-N56U twin**: same SoC, flash layout and bootloader, but a different switch chip (RTL8367R-VB on
bit-banged SMI, GPIO22/23) and an extra DSL co-processor on switch port 0. The switch is why RT-N56U images have no Ethernet here.

## 2. What works under OpenWrt 25.12.6

| Feature | State |
|---|---|
| 4× gigabit LAN (RTL8367R-VB, swconfig) | ✅ front label LAN1 = switch port 4 |
| 5 GHz (on-SoC RT3883, `rt2800soc`) | ✅ AP heard by clients |
| 2.4 GHz (PCI RT3092, `rt2800pci`) | ✅ AP heard by clients |
| Flash / overlay | ✅ 2.25 MB jffs2 `rootfs_data` |
| `sysupgrade` (keep settings) | ✅ verified: config, keys, password survive (~4 min) |
| SSH Ed25519 keys | ✅ with `CONFIG_DROPBEAR_ED25519=y` (not in stock OpenWrt small-flash builds) |
| LEDs (power, WAN), reset + WPS buttons | ✅ |
| USB 2.0 ports | ✅ both ports; mass storage (FAT32/exFAT) read at ~16-24 MiB/s with `kmod-usb-storage` (built as packages) |
| Wi-Fi on/off slide switch | ✅ `EV_SW` `KEY_RFKILL` on GPIO1: off → radios disabled, on → enabled (also applied at boot) |
| DSL | ❌ not supported (TC3162LE co-processor, isolated on switch port 0) |

## 3. Installing OpenWrt (no serial console needed)

You need a Linux host with **nix (flakes)** and **podman**, and a cable from the host to a router **LAN** port. Give the host
`192.168.1.10/24` **and** `192.168.1.11/24` on that NIC, with no gateway. (.11 is what the bootloader talks to in rescue mode.)

```sh
nix develop                                  # all tools: nmap, tcpdump, tftp-hpa, binwalk, sasquatch, radare2, ...
export DSL_LAN_IF=<your NIC>                 # default enp3s0
```

1. **Stock firmware prep.** Factory reset, log in (`admin`/`admin`), then *Administration → System → Enable Telnet*.
   Telnet logs in with the web credentials as root (`scripts/tn.py 'cmd'`).
2. **Back up the whole flash first.** The `Factory` partition holds this unit's Wi-Fi calibration and MACs and cannot be
   recreated. Run `in.tftpd -L -c -s <dir>` on the host, then on the router
   `tftp -p -l /dev/mtdNro -r mtdN.bin <host>` for N = 0..3. Compare md5s on both sides. See `docs/session-log.md`.
3. **Build the image** (or reuse one you trust):
   ```sh
   WIFI_COUNTRY=XX openwrt-port/apply.sh      # clone OpenWrt v25.12.6, apply the port, seed .config
   podman build -t dsl-n55u-owrt openwrt-build/
   openwrt-build/run.sh bash -c './scripts/feeds update -a && ./scripts/feeds install -a && make defconfig && make -j$(nproc)'
   # -> openwrt/bin/targets/ramips/rt3883/openwrt-ramips-rt3883-asus_dsl-n55u-squashfs-sysupgrade.bin
   ```
4. **Flash from the stock shell:**
   ```sh
   scripts/flash-openwrt.sh <sysupgrade.bin>        # dry run: checks, download to router RAM, md5, cache warm-up
   scripts/flash-openwrt.sh <sysupgrade.bin> --go   # mtd-write, read-back verify, reboot
   ```
5. **First boot** (~90 s): `http://192.168.1.1` / `ssh root@192.168.1.1`. **Set a root password immediately.** Set the Wi-Fi
   country. The bring-up image also starts a WPA2 AP `DSL-N55U-setup` (key generated into `backup/`) as a fallback way in.

Later upgrades use plain OpenWrt sysupgrade (LuCI → System → Backup / Flash firmware).

**USB storage** packages are built alongside the image but not included in it. Install them from
`openwrt/bin/targets/ramips/rt3883/packages/` (`kmod-usb-storage`, `kmod-fs-vfat`, `kmod-fs-exfat`, `kmod-nls-*`) with
`apk add --no-network --allow-untrusted ...`. They must come from the **same build** as the running image (the kernel hash must match).

### Using it as a cascaded switch + backup AP

`scripts/owrt.sh 'sh -s' < scripts/owrt-switch-mode.sh` turns the unit into an L2 switch for a remote spot: one LAN port
up to the main switch, the others to local devices. The RTL8367 forwards between ports in hardware at gigabit speed. The
script:
- makes LAN a **DHCP client** (hostname `dsl-n55u`) and keeps **192.168.1.1/24 as a fallback** management address,
- turns off the DHCP server, IPv6 RA/DHCPv6/NDP, `odhcpd` and the ULA prefix, so there are no rogue services on the main LAN,
- moves Wi-Fi to non-overlapping 20 MHz channels (edit `CH2`/`CH5` after a site survey).

It arms a **3-minute automatic rollback** that only stops if you `touch /tmp/net-confirmed` on the router after checking
it's still reachable. Verified here: a broadcast DHCP discover got no answer and there were zero RAs on the wire.

Why not the stock web UI or rescue mode? See [docs/04-openwrt-port.md](docs/04-openwrt-port.md#image-format-constraints-why-the-flashing-plan-is-what-it-is):
DSL rescue only writes `ih_size + 64` bytes and checks the productid, and OpenWrt's `mtdsplit` needs a kernel-only `ih_size`.

## 4. Going back to stock (rescue mode)

1. `scripts/rescue-flash.sh` (defaults to ASUS's 376_2736 rescue image, fetched with `scripts/fetch-firmware.sh`).
2. Power off → hold **RESET** → power on → keep holding ~15 s → release. **There is no LED indication** on this model.
3. The script detects rescue mode (ARP answers, no TCP services), uploads, and waits for stock to boot (≈ 4-5 min total).

The bootloader also drops into rescue **by itself** if the firmware fails its CRC check, so a botched write is recoverable.
Our unit's reset switch was dead (residue around its pins suggests corrosion); wires soldered to its two front pins and bridged at power-on work just as well.
Details and the bootloader source analysis: [docs/03-bootloader-and-recovery.md](docs/03-bootloader-and-recovery.md).

## 5. Hazards and gotchas (read before touching the unit)

- **Rescue mode writes any upload of ≤ 0x30000 bytes over the bootloader itself.** Only ever send a full firmware image.
  (`rescue-flash.sh` and `uimage_check.py --rescue` refuse anything else.)
- **WPS held at power-on erases nvram** (factory reset). RESET held at power-on = rescue mode.
- On stock firmware, **RESET held ≥ 2 s while running = factory reset** (except in `asus_mfg=1` test mode).
- Stock defaults: **open** SSIDs `ASUS`/`ASUS_5G`, WPS on, `admin`/`admin`. Keep the Wi-Fi switch off on stock.
- U-Boot's rescue TFTP server **replies to `serverip` 192.168.1.11** instead of the sender, and **locks onto the UDP source
  port of the first write request**. Use one fixed source port (`tftp-hpa -R P:P`). `rescue-flash.sh` handles both.
- BusyBox `telnetd` on stock **kills background jobs when the session closes**. Long-running or reboot commands must run in
  the foreground of a session that stays open.
- Overwriting the running stock firmware: pre-read the whole stock rootfs into the page cache first (`flash-openwrt.sh` does)
  so nothing faults in from the flash being overwritten.
- **SSH keys on the OpenWrt side** (three traps, all hit while bringing this unit up):
  1. OpenWrt's dropbear reads root's keys **only from `/etc/dropbear/authorized_keys`**. `ssh-copy-id` writes
     `/root/.ssh/authorized_keys`, which is ignored. Use LuCI → System → Administration → SSH-Keys, or append to the right file.
  2. Stock OpenWrt builds dropbear **without Ed25519 on `small_flash` targets like this one**: Ed25519 keys are silently
     refused and the server offers only an RSA host key. `openwrt-port/diffconfig` sets `CONFIG_DROPBEAR_ED25519=y`;
     images built before that change only accept RSA keys.
  3. Terminal SSH wrappers can eat stdin. Ghostty's shell integration ("Setting up xterm-ghostty terminfo") made
     `cat keys | ssh host 'cat >> authorized_keys'` write terminfo text instead of keys. Use `command ssh` for piped commands.

## 6. Stock firmware security findings (summary)

| # | Finding | Status |
|---|---|---|
| F1 | Firmware updates are unsigned (CRC only), downloaded over plain HTTP; the manifest uses HTTPS with `--no-check-certificate` | all versions |
| F2 | Pre-auth stack overflow in httpd `Accept-Language` parsing (`strcpy` into 256 B) | 376_2736; fixed silently in 380 |
| F3 | Pre-auth unbounded copy into a global `url[128]` | 376_2736 (380 unchecked) |
| F4 | Basic auth over HTTP; IP-bound "sessions"; settings endpoints unauthenticated until the setup wizard completes | all |
| F5 | dnsmasq 2.72/2.76 (CVE-2017-14491.., DNSpooq), pppd 2.4.5/2.4.7 (CVE-2020-8597), Linux 2.6.22, BusyBox 1.17.4 | all |
| F6 | Process-global `skip_auth` flag → full auth bypass from the logged-in IP on a fresh unit (verified live) | 376_2736 |
| F7 | Unauthenticated `state.js` and status pages leak build, SSIDs, WAN state (verified live) | 376_2736 |
| F8 | Admin password in plaintext in nvram; WPS PIN in nvram; open Wi-Fi defaults | all |
| F9 | Bootloader: unsigned rescue flashing; small uploads overwrite the bootloader; WPS-at-boot wipes config | bootloader 2011 |

Full write-up with code references and reproduction: [docs/02-stock-firmware.md](docs/02-stock-firmware.md).
Nothing was exploited; the memory-corruption bugs are documented from source and binaries only.

## 7. Notes for AI agents and automation

- **Read first:** this README, then `docs/03-bootloader-and-recovery.md` (recovery is the safety net) and
  `docs/04-openwrt-port.md`. `docs/session-log.md` has the chronology, including dead ends.
- **Tools:** run everything inside `nix develop`. Raw-socket tools need root: `sudo $(command -v tcpdump)`. In a git
  checkout the flake must be tracked (or `git add -N flake.nix flake.lock`), or nix won't see it.
- **Talking to the device:** stock → `scripts/tn.py [-s] 'cmd' ...` (telnet; output is cleanly bracketed per command).
  OpenWrt → `scripts/owrt.sh 'cmd'` (SSH as root; needs key auth once a password is set).
- **Before any flash write**, run `scripts/uimage_check.py [--rescue] <image>`. It replays the bootloader's exact checks.
- **Destructive actions** (flash writes, rescue uploads, factory resets, deliberately corrupting headers) need the human's
  explicit OK each time. Never delete or overwrite `backup/`.
- **Lab conventions** used by the scripts: router at 192.168.1.1, host .10 + .11 on `$DSL_LAN_IF`, no default route via the
  router, host `ip_forward=0` (so a stock unit never reaches the internet).
- **Shell traps seen on the original host:** zsh does not word-split `$VAR` command strings and treats a bare `===` as a
  command, and `grep` was aliased to ugrep. Prefer small scripts over clever one-liners.

## 8. Repository layout

```
README.md              this file
docs/01-hardware.md    SoCs, flash map, GPIO table, switch wiring, radios, board photos
docs/02-stock-firmware.md          image format, components, security findings F1-F9
docs/03-bootloader-and-recovery.md U-Boot boot flow, rescue mode rules and quirks, recovery procedures, button tests
docs/04-openwrt-port.md            port design, build, flashing, first-flash verification, OPNsense verdict
docs/session-log.md                chronological log
openwrt-port/          the port: patch against OpenWrt v25.12.6, first-boot files, diffconfig, apply.sh (source of truth)
openwrt-build/         Containerfile + runner for the OpenWrt build (Debian bookworm, rootless podman)
scripts/               tools (table below)
scans/ captures/       evidence: nmap output, fake-ISP logs, rescue link timeline
loot/                  MANIFEST.md (hashes of stock web-UI pages fetched; the pages are ASUS's, kept local) + live sysinfo
flake.nix              devShell
(gitignored) firmware/ vendor images + GPL tree + U-Boot source · backup/ flash dump + keys · openwrt/ checkout + build
            openwrt-ref/ upstream reference DTS (fetch: openwrt/target/linux/ramips/dts/rt3662_asus_rt-n56u.dts, rt3883_asus_rt-n65u.dts)
```

| Script | Purpose |
|---|---|
| `scripts/fetch-firmware.sh [--gpl]` | Download all stock images (+585 MB GPL source) from ASUS's CDN into `firmware/dl/` |
| `scripts/extract.sh <zip\|trx> <out>` | Split a stock image (uImage → kernel, squashfs 3.0/LZMA rootfs, DSL trailer) and unpack it |
| `scripts/tn.py [-s] 'cmd' ...` | Run commands over the stock telnetd; `-s` streams output live |
| `scripts/owrt.sh 'cmd'` | Run commands on an OpenWrt-flashed unit over SSH |
| `scripts/owrt-switch-mode.sh` | Run on the router (`owrt.sh 'sh -s' < ...`): cascaded switch + backup AP config, with auto-rollback |
| `scripts/uimage_check.py [--rescue] <img>` | Offline replay of the bootloader's boot-time / rescue-mode image checks |
| `scripts/flash-openwrt.sh <img> [--go]` | Install OpenWrt from the stock shell (env `HOST_IP`, default 192.168.1.10) |
| `scripts/rescue-flash.sh [img]` | Wait for rescue mode, then TFTP a stock image (handles the U-Boot quirks) |
| `scripts/button-test.sh [secs]` | Live button test on stock, safe from the 2 s factory reset (`asus_mfg` mode) |
| `scripts/fake-isp.sh up\|down` | Pose as the router's ISP (DHCP, catch-all DNS/HTTP, pcap) on an isolated subnet |
| `openwrt-port/apply.sh` | Clone OpenWrt at the pinned tag, apply the port (env `WIFI_COUNTRY`) |
| `openwrt-build/run.sh <cmd>` | Run a command in the OpenWrt build container |

## 9. License

- **Our work** (scripts, Nix/podman build setup, documentation, photos, and our original additions in `openwrt-port/`) is
  released under the **MIT License**, see [LICENSE](LICENSE).
- `openwrt-port/0001-*.patch` modifies OpenWrt build files, which are GPL-2.0 (OpenWrt's license applies once it is applied to
  that tree). The new device tree carries `SPDX-License-Identifier: GPL-2.0-or-later OR MIT`, as is usual for OpenWrt DTS, so it can be
  upstreamed.
- **ASUS's code belongs to ASUS.** Firmware images, the GPL source tarball, the U-Boot source and the stock web UI are
  © ASUSTeK Computer Inc. (GPL components under their respective licenses). None of it is redistributed here: the scripts
  download it from ASUS. The docs quote only short excerpts and cite file/line for analysis, and the fetched web-UI pages
  are recorded by hash only (`loot/MANIFEST.md`). ASUS, ASUSWRT and DSL-N55U are trademarks of ASUSTeK; this project is
  not affiliated with or endorsed by ASUS.

## 10. Upstream status

As of 2026-11-02 the DSL-N55U is **not** in OpenWrt and has never been submitted: there are no `openwrt/openwrt` PRs,
issues or code mentioning it, and nothing on openwrt-devel or patchwork. There is only the 2024 forum feature request. The device tree,
image recipe and `02_network` hunk in `openwrt-port/` are written to be upstreamable. The bring-up uci-defaults and
`diffconfig` are local conveniences, not upstream material.

## 11. References

- ASUS GPL source `GPL_DSL_N55U_30043762736.zip` (includes the U-Boot source) and firmware images, from dlcdnets.asus.com
  via ASUS's support API (`scripts/fetch-firmware.sh`).
- OpenWrt forum: "ASUS DSL-N55U(-B) support" (forum.openwrt.org/t/195217): the RT-N56U image boots, Ethernet doesn't.
- WikiDevi / DeviWiki: ASUS DSL-N55U hardware entries.
- OpenWrt `target/linux/ramips` (rt3883 subtarget), `rtl8367b.c`, `mtdsplit_uimage.c`.
