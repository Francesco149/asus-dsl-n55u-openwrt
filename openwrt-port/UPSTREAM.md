# Upstream submission: `ramips: add support for ASUS DSL-N55U`

Status (2026-11-02): **committed and pushed to the fork for review; not submitted upstream.** Branch `ramips-asus-dsl-n55u` on
https://github.com/Francesco149/openwrt (fork of openwrt/openwrt), based on `main`.
Nobody had submitted this device before (GitHub PRs/issues/code, openwrt-devel, patchwork searched).

Upstream-only differences from `0001-ramips-add-support-for-ASUS-DSL-N55U.patch` (which targets v25.12.6):
- `sda-gpios`/`sck-gpios` instead of `gpio-sda`/`gpio-sck`: the rtl8366_smi driver on `main` uses `devm_gpiod_get()`
  (treewide change of 2025-12-23).
- Trimmed DTS comments; no bring-up uci-defaults, no diffconfig (local conveniences only).
- LAN MAC handled like the RT-N56U (`macaddr_setbit_la`). The 5 GHz WMAC EEPROM carries the same address as factory 0x4.

Before submitting (human):
- [x] `Signed-off-by: Francesco Noferi <cute@headpats.uk>` (matches the commit author).
- [x] Label MACs: the sticker prints both "MAC 2.4GHz" (factory 0x8004) and "MAC 5GHz" (factory 0x4); `label_mac` = factory 0x4.
- [x] Front LAN1-4 = switch ports 4-1 (verified by moving a cable through all four ports).
- [ ] Review the commit message below.

## Commit message

```
ramips: add support for ASUS DSL-N55U

The ASUS DSL-N55U is an ADSL2+ modem router based on the same platform as
the ASUS RT-N56U, but with a Realtek RTL8367R-VB switch on GPIO
bit-banged SMI and an additional TrendChip TC3162LE DSL co-processor
attached to switch port 0. DSL is not supported; the device works as a
4-port router, switch or access point.

This applies to the original hardware revision (A1 Annex A, B1 Annex B;
stock firmware 3.0.0.4.x/9.0.0.4.x). C1 and D1 are unrelated designs.

Specifications:
- SoC:      Ralink RT3662F (MIPS 74Kc, 500 MHz)
- RAM:      128 MiB DDR2
- Flash:    8 MiB parallel NOR (CFI)
- Ethernet: 4x 1 GbE LAN (Realtek RTL8367R-VB)
- WLAN:     2.4 GHz: Ralink RT3092 (PCI), b/g/n, 2T2R
            5 GHz: RT3662 (SoC), a/n, 2T3R
- USB:      2x USB 2.0
- Buttons:  Reset, WPS, Wi-Fi on/off slide switch
- LEDs:     Power, WAN (LAN LEDs are driven by the switch)
- Serial:   4-pin header (pinout not verified), ttyS1, 57600 8N1

Installation:
The stock web interface only accepts images with the ASUS product ID,
and the bootloader's rescue mode of this DSL model only writes the
first ih_size + 64 bytes, so OpenWrt has to be written from the stock
firmware's shell:
1. Enable Telnet in Administration -> System and log in with the web
   interface credentials.
2. Download the sysupgrade image to /tmp, e.g. with wget.
3. mtd-write -i /tmp/openwrt-sysupgrade.bin -d linux
4. Reboot, e.g. with "echo b > /proc/sysrq-trigger".

Recovery:
Hold reset while powering on to enter the bootloader's rescue mode (the
power LED gives no indication on this model) and upload the stock
firmware with TFTP to 192.168.1.1. The bootloader sends its replies to
its "serverip" 192.168.1.11 instead of the requester, so the TFTP client
needs that address, and every retry must use the source port of the
first write request. The bootloader also enters rescue mode by itself
if the firmware fails its CRC check.

MAC addresses:
- LAN:     factory 0x4 with the locally administered bit set
           (the 5 GHz radio uses the same address, as on the RT-N56U)
- 2.4 GHz: factory 0x8004 (label "MAC 2.4GHz")
- 5 GHz:   factory 0x4    (label "MAC 5GHz")

Signed-off-by: Francesco Noferi <cute@headpats.uk>
Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
```

## Pull request description

```
Adds support for the original ASUS DSL-N55U (RT3662F + RTL8367R-VB).
See the commit message for specifications, installation and recovery.

Testing:
- Run-tested on OpenWrt 25.12.6 (kernel 6.12) with the same device tree
  (except the sck/sda-gpios rename): RTL8367R-VB detected via GPIO SMI,
  cpu_port 5 on extif1, all four LAN ports, both radios as AP, USB
  storage on both ports, reset/WPS buttons, Wi-Fi slide switch (rfkill),
  LEDs, jffs2 overlay and sysupgrade with kept settings. Front LAN1-4
  map to switch ports 4-1 (checked port by port).
- Build-tested on main @ c1bd42c (kernel 6.18): image builds, DTB has
  sda/sck-gpios on GPIO 22/23 and the rfkill EV_SW key.

Background, bootloader analysis and recovery tooling:
https://github.com/Francesco149/asus-dsl-n55u-openwrt
```
