# Session log

Chronological record of the work, including dead ends and corrections. Times are host local time (CET).

## 2026-11-02

**Environment**
- The host had almost no network tools, and its pacman db was stale (nmap 404 on mirrors). Some tools were installed via pacman,
  then **removed again** once the user asked for a self-contained env → `flake.nix` devShell (nix with flakes is available).
  Rule since then: no host package installs. Use the flake or podman.

**First contact (router in its previous owner's config)**
- Passive sniff on `enp3s0`: the router sent DHCP DISCOVERs (`udhcp 1.17.4`, MSZ 1492) from e0:3f:49:XX:XX:68.
- Built `scripts/fake-isp.sh` (dnsmasq DHCP + catch-all DNS → host, HTTP logger, pcap, ip_forward off) and leased
  172.30.55.142 to it. Only phone-home seen: DNS `pool.ntp.org`.
- nmap: 80, 515, 3394, 3838, 5473, 9100, 9998, 18017 wanduck, 45677 MiniUPnPd 1.4; UPnP rootDesc gave
  `modelNumber 3.0.0.4.376`. `/error_page.htm` was unauthenticated (LAN IP 192.168.2.1, no password leak).
- **Correction:** this was first written up as "services exposed on the WAN side". The user confirmed the cable was in
  **LAN port 1**, so the router was in AP mode (DHCP client on LAN) and the exposure is by design. The finding was dropped.
- One turn was stopped by a safety classifier while probing those services further. Live-device work since then sticks to
  observation and verification. Memory-corruption bugs are documented from source/binaries only.

**Firmware acquisition and analysis**
- ASUS support API → exact filenames. Downloaded all A/B images plus the GPL tarball (`scripts/fetch-firmware.sh`).
- The `.trx` is a uImage. The squashfs is 3.0/LZMA at a variable offset (sasquatch). Wrote `scripts/extract.sh`.
- Findings F1 (unsigned/insecure updates), F2 (pre-auth `Accept-Language` stack overflow; `strcpy` in 376, `strncpy` in 380),
  F3 (`url[128]`), F5 (old components). Details in `02-stock-firmware.md`.
- Hardware from WikiDevi + GPL: RT3662F + TC3162LE, RTL8367R-VB on GPIO22/23, same flash layout as the RT-N56U.

**Factory reset**
- The first reset-button attempt didn't reset it (still 192.168.2.1, still asking for a login). The router was reachable only via its
  remaining fake-ISP lease 172.30.55.142. Then the user reported it reset: 192.168.1.1, MAC ...:6c.
- Live: firmware **3.0.0.4.376_2736-ge8d4e19** (== the analyzed image), `rc_support` without `HTTPS`.
- Found F6 (global `skip_auth`), F7 (unauth `state.js` etc.), F4 (NOAUTH_FIRST `start_apply.htm`).
- Enabled telnet via the stock System form (authenticated `start_apply.htm`, `telnetd_enable=1`, `restart_time`).
  Side effect: `x_Setting=1`. Root shell via `scripts/tn.py`.
- **Full flash backup** over BusyBox `tftp -p` from `/dev/mtdNro` to host `in.tftpd`: 4 partitions, md5 = the router's own md5s.
  `backup/flash/`.
- From the dumps: U-Boot 1.1.3 (2011), Factory MACs/EEPROMs, nvram with **plaintext** `http_passwd`, WPS PIN `secret_code` (F8).
  Radios off (`wl*_radio=0`); defaults are open SSIDs with WPS on.

**OpenWrt / OPNsense**
- User preference: flash without UART if possible ("if we brick it we can hardware flash it back").
- OPNsense ruled out (x86-64 only; requirements far beyond this hardware).
- OpenWrt 25.12.6 still builds rt3883/RT-N56U. Cloned v25.12.6.
- The ASUS U-Boot source in the GPL showed: boot check = CRC only; rescue = productid + CRC, writes only `ih_size+64`,
  ≤0x30000 → bootloader overwrite; the rescue LED blink is compiled out; WPS at boot wipes nvram.
- OpenWrt's `mtdsplit_uimage` needs `ih_size` = kernel only. So: no factory image, no rescue install. Flash from the stock shell
  with `mtd-write` (raw writer on Ralink) instead. Stock rescue image = recovery.
- Wrote the DTS/image/network changes. Verified on the live device: `switch IC = CHIP_RTL8367R_VB`, PCI 1814:3091,
  GPIOMODE 0x189f. Added a first-boot WPA2 fallback AP.
- Build container (`openwrt-build/`, Debian bookworm, rootless podman). Feeds + defconfig; full build started (~17:52).
- Scripts: `uimage_check.py` (validated: stock rescue image ACCEPT, the OpenWrt-style image REJECTED for rescue),
  `rescue-flash.sh`, `flash-openwrt.sh`.

**Rescue-mode attempts**
- Two power-on-with-reset attempts → normal boot both times (see the table in `03-bootloader-and-recovery.md`).
- U-Boot `bootdelay=1`; `DETECT()` samples the button once. There is no LED cue on this model.
- Button test via `asus_mfg=1`: the first logger died with its telnet session; repeated with a persistent session.

**Dead reset switch, then rescue success**
- `asus_mfg` button test (persistent session): WPS registered, RESET never. Case opened: SRW3 has no continuity when pressed
  (WPS does). There's green/yellow residue around its pins. Board photos in `docs/img/`.
- Live test: shorting SRW3's front pins → `reset=1` in Linux, so the GPIO3 net is fine.
- Three power-on attempts with tweezers/wires → normal boots. Ruled out a bootloader/source mismatch (prebuilt
  `u-boot.srec` = device mtd0 except 10 bytes: timestamps + the Annex A/B productid) and disassembled `DETECT`/GPIO code: it reads GPIO3 correctly.
- Fourth attempt with soldered wires → **rescue mode**. The upload initially hung because of two U-Boot TFTP quirks (ACK to
  `serverip` 192.168.1.11; locked to the first WRQ's source port). Fixed live (added .11, re-sent from port 41947):
  stock rescue image written and verified by md5. `rescue-flash.sh` and `tn.py` (output bracketing) fixed accordingly.

**OpenWrt flashed (~20:12-20:20)**
- `flash-openwrt.sh --go`: written, md5 verified. The backgrounded reboot didn't happen (telnetd kills bg jobs); a manual sysrq
  reboot worked. OpenWrt was up on wired LAN in ~90 s, and the user saw LuCI first.
- Verified: board id, RTL8367R-VB via GPIO SMI + extif1, ports (LAN1 = port 4, DSL CPU on port 0), jffs2 overlay, kernel CRC
  region intact, LEDs, keys, both radios AP-ENABLED. Bug: the bring-up script didn't enable the wifi-ifaces (fixed in the repo,
  enabled by hand on the device). With antennas off, only the 5 GHz AP was heard from the host. Wi-Fi switch polarity measured.
- Rebuild with fixes (LAN labels, uci-defaults, DTS notes) started; `flash-openwrt.sh` reboot step fixed.

**Publishing, SSH keys, upgrade (evening)**
- Committed, redacted (MACs/BSSIDs, host MAC, UPnP UUID), ASUS web-UI pages replaced by a hash manifest, MIT LICENSE, and
  published to GitHub.
- Key login failed three ways: `ssh-copy-id` → wrong file for dropbear; Ghostty's ssh wrapper ate the piped stdin (wrote
  terminfo into authorized_keys); dropbear built without Ed25519 on small_flash. Bridged with a temporary RSA key, set country IT
  (5 GHz 23 dBm), and confirmed both bands from a client (2.4 GHz 89 %, 5 GHz 40 %, antennas on).
- Rebuild with `CONFIG_DROPBEAR_ED25519=y` and a guarded bring-up script, installed via `sysupgrade` (settings kept, ~4 min):
  Ed25519 login works, all settings survived, temporary RSA key removed.

**Switch role, USB, Wi-Fi switch, upstream check (late evening)**
- Role: cascaded L2 switch + backup AP. `owrt-switch-mode.sh` was applied with a 3-minute rollback and confirmed. No DHCP
  offers and no RAs on the wire. Wi-Fi moved to 2.4 GHz ch 1 / 5 GHz ch 149 after a survey (the upstream AP uses 5 GHz 36-48 at 80 MHz).
- USB: both ports enumerate card readers at 480 Mbit/s. The usb-storage kmods first failed to install (kernel hash changed when
  they were enabled), so they went into rebuild #4 with the rfkill slide-switch mapping. sysupgrade, then the kmods installed;
  64 GB FAT32 and 32 GB exFAT cards read fine (read-only, no file listing).
- Slide switch tested live: off disables both APs, on re-enables them.
- Upstream: nobody has submitted the DSL-N55U to OpenWrt (GitHub, openwrt-devel, patchwork searched).

**Documentation**
- Moved `NOTES.md` into `README.md` + `docs/`. Exported the OpenWrt port as `openwrt-port/` (patch + files + diffconfig + apply.sh).
  `git init` with a `.gitignore` that keeps vendor blobs, the OpenWrt checkout and `backup/` out of git.
