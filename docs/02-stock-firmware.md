# Stock firmware and security review

Educational review of the end-of-life ASUS DSL-N55U stock firmware, on hardware we own.
Unless stated otherwise, findings were confirmed by source (ASUS GPL 3.0.0.4.376_2736), by disassembly, and/or
by observation on the live device. Nothing was exploited. Memory-corruption bugs are documented from source and
binaries and were **not** triggered on the device.

## Firmware versions

From ASUS's support API (`GetPDBIOS?model=DSL-N55U`), fetched with `scripts/fetch-firmware.sh`:

| Version | Date | Notes |
|---|---|---|
| 3.0.0.4.374_159 | 2013-08 | rescue image (Annex B) |
| **3.0.0.4.376_2736** | 2015-01-19 | last "release". Changelog: "Fixed infosvr security issue", "Fixed CSRF". **Running on our unit** (`extendno=2736-ge8d4e19`) |
| 9.0.0.4.380_3925 | 2016-08-04 | final **beta**. "Enhanced login authentication, fixed CSRF, multiple security issues" (credits SEC Consult / Pichaya Morimoto) |

GPL source exists only for 376_2736 (`GPL_DSL_N55U_30043762736.zip`, 585 MB, still on dlcdnets.asus.com).

## Image format

The `.trx` is really a **U-Boot legacy uImage**:
- 64-byte header. `ih_name` carries ASUS fields: `[0..3]` version bytes (`03 00 00 04` = 3.0.0.4),
  `[4..]` productid `DSL-N55U` (absolute offset 36), and the last 4 bytes `a9 0f 5b 00`, i.e. a marker byte 0xa9 plus a 24-bit
  kernel size / squashfs offset (0x0f5b00).
- LZMA kernel (Linux **2.6.22.19**, built with gcc **3.4.2**), then **squashfs 3.0 with LZMA** at a variable offset
  (0xF5B00 in 376). Use `sasquatch`; binwalk misses it.
- `ih_size` covers kernel + rootfs. After the uImage comes a **DSL trailer**: two LZMA blobs (≈66 KB + ≈995 KB uncompressed),
  the TC3162 modem firmware. ASUS's *rescue* image is the same uImage without the trailer.
- `scripts/extract.sh` splits all of this. Extracted trees: `firmware/x/376A`, `firmware/x/380A`, `firmware/x/rescue376A`.

## Components

| | 376_2736 | 380_3925 |
|---|---|---|
| Kernel | Linux 2.6.22.19 (2007), gcc 3.4.2 (2004) | same |
| BusyBox / udhcp | 1.17.4 (2010) | same |
| dnsmasq | 2.72test3 | 2.76 |
| pppd | 2.4.5 | 2.4.7 |
| MiniUPnPd | 1.4 | 1.9 |
| vsftpd / iptables | 2.0.4 / 1.3.8 | same |
| libc | uClibc | same |

The final 2016 firmware still ships the 2007 kernel and the 2010 userland base. ASUS only patched individual daemons.

Services (stock, LAN side, factory defaults; `scans/lan-default-*`): 53 dnsmasq, 80 httpd, 515/9100 printing,
3394/3838/5473 USB-over-IP helpers, 9998, 18017 wanduck, high-port MiniUPnPd, UDP 53/67, 1900 SSDP, 5351 NAT-PMP,
9999 infosvr (open|filtered), 18018. Telnet (23) when enabled; there is no SSH in this build.

## Findings

### F1. Firmware updates are unauthenticated and fetched insecurely (376 and 380)
- `check_imageheader()` / `checkcrc()` (`src/router/shared/sysdeps/api-ralink.c:103-230`) accept any image with uImage
  magic, valid header and data CRC32, and `ih_name+4 == productid`. **There is no signature.**
- `webs_upgrade.sh` runs an RSA check only if `rc_support` contains `HTTPS`. `RTCONFIG_HTTPS` is not set for
  DSL-N55U (`src-ra/target.mak:44`), neither image ships `rsasign_check`, and the live `rc_support` lacks `HTTPS`.
- Firmware is downloaded over **plain HTTP** (`http://dlcdnet.asus.com/...`). The update manifest uses HTTPS but with
  **`--no-check-certificate`** (`webs_update.sh`).
- Impact: a network-path attacker (or rogue DNS) can serve persistent malicious firmware when the owner clicks
  upgrade. Any admin session or CSRF can flash arbitrary code. (Upside: custom firmware needs no signing.)

### F2. Pre-auth stack buffer overflow in httpd `Accept-Language` parsing (376; silently fixed in 380)
- `src/router/httpd/httpd.c:741-746` (compiled in via `-DTRANSLATE_ON_FLY`, `httpd/Makefile:6`):
  `char lang_buf[256]; strcpy(lang_buf, alang);`. `alang` is the raw header, bounded only by the 10 000-byte request line
  buffer. This runs **before authentication**.
- Binaries: 376 `httpd` @0x405304 calls `strcpy`. 380 @0x406754 calls `strncpy(lang_buf, alang, 0xff)`.
- Context: no stack protector (gcc 3.4.2), Linux 2.6.22 on MIPS (no NX/ASLR to speak of), httpd runs as root.
  **Not triggered on the device.**

### F3. Pre-auth unbounded copy into the global `url[128]` (376; 380 not yet checked)
- `httpd.c:239` `char url[128];`, and `:864-877` `strncpy(url, file, file_len)` / `strcpy(url, file)` with the
  request path (up to ~10 000 bytes). This overflows `.bss` before the auth check.

### F4. Weak authentication model
- HTTP Basic auth over plaintext HTTP. Credentials travel base64-encoded on every request.
- The "session" is just the client IP (`login_ip`). Anyone else behind that IP inherits the login.
- While `x_Setting=0` (factory default / wizard not finished), pages flagged `MIME_EXCEPTION_NOAUTH_FIRST` are served
  without auth (`httpd.c:941`). These include the **settings endpoints `start_apply.htm`/`start_apply2.htm`**
  (`web.c:6444-6445`), so any LAN client can reconfigure a fresh unit, including its admin password.

### F5. Known-vulnerable third-party components
- dnsmasq 2.72test3 / 2.76 (< 2.78): CVE-2017-14491..14496. Also < 2.83: DNSpooq, CVE-2020-25681..25687.
- pppd 2.4.5 / 2.4.7: CVE-2020-8597 (EAP `rhostname` stack overflow, pre-auth from the PPP peer, i.e. the ISP side).
- Linux 2.6.22.19, BusyBox 1.17.4, vsftpd 2.0.4, iptables 1.3.8, MiniUPnPd 1.4: years of unpatched CVEs.

### F6. Process-global `skip_auth` turns the wizard exception into a full auth bypass (verified live)
- `skip_auth` is a global in httpd (`httpd.c:234`). Requesting any NOAUTH_FIRST file (`QIS_*`, `*.css`, `state.js`, ...)
  while `x_Setting=0` sets it to 1 (`httpd.c:941-942`). It is cleared only when `http_login_check()` reports
  *nobody* logged in. While the logged-in IP's session lives, **every** page from that IP skips auth.
- Observed on the reset router: `index.asp` and `Advanced_System_Content.asp` returned 200 with no credentials after
  this host had fetched `state.js` (see `loot/MANIFEST.md`; the pages themselves are ASUS's and not published).

### F7. Unauthenticated information disclosure (verified live)
- `state.js` without auth is byte-identical (except uptime) to the authenticated copy: firmware build, `rc_support`,
  SSIDs, WAN/dual-WAN state (`state-noauth.js` vs `state-default.js` in `loot/MANIFEST.md`).
- Always unauthenticated (NOAUTH_ALL, `web.c:6433-6471`): `WAN_info.asp`, `detect_firmware.asp`, `update_appstate.asp`,
  `update_cloudstatus.asp`, `error_page.htm` (shows LAN IP + netmask), `Nologin.asp`, `httpd_check.htm`.
  Unlike some older ASUSWRT builds, `error_page.htm` here does *not* leak the password.

### F8. Secrets at rest and insecure defaults (verified live)
- nvram (mtd1) stores `http_passwd` in **plaintext**. Telnet logs in with the same credentials as uid 0
  (`chpass(http_username, http_passwd)` in `start_telnetd`).
- `secret_code` in nvram = the WPS device PIN. `wps_enable=1` by default.
- Factory Wi-Fi defaults are **open** (`wl*_auth_mode_x=open`, SSIDs `ASUS` / `ASUS_5G`) with admin/admin. Only the radio
  switch stands between a neighbor and a root shell.

### F9. Physical-access weaknesses in the bootloader (from U-Boot source)
- Rescue mode (reset held at power-on, or any image that fails CRC) accepts **any image with the right productid and
  CRCs**. No signature.
- A rescue upload of ≤ 0x30000 bytes **overwrites the bootloader** (`cmd_tftpServer.c` ~L595-640). That's a bricking footgun.
- Holding **WPS at power-on silently erases nvram** (`common/gpio.c: DETECT()`).
- U-Boot's serial menu offers "Load Boot Loader code then write to Flash via TFTP".
- These are typical for consumer gear but worth knowing; see [03-bootloader-and-recovery.md](03-bootloader-and-recovery.md).

## Open items
- [ ] F3 in the 380 binary.
- [ ] infosvr (UDP 9999, CVE-2014-9583): ASUS claims it was fixed in 376_2736. Check `src/router/infosvr`.
- [ ] What the 376_2736 "CSRF fix" actually checks (Referer?).
- [ ] WAN-side exposure in router mode (needs an EWAN or DSL configuration).

## Phone-home behavior

Observed by posing as the ISP (`scripts/fake-isp.sh`) while the unit was in AP mode: only a DNS query for `pool.ntp.org`;
no HTTP update check during the observation window. The update path is in F1.

## Methodology / reproduction

```sh
nix develop
scripts/fetch-firmware.sh --gpl
scripts/extract.sh firmware/dl/FW_DSL_N55U-30043762736_Annex_A/*.zip firmware/x/376A
scripts/extract.sh firmware/dl/FW_DSL_N55U_90043803925/*.zip        firmware/x/380A
# GPL: bsdtar -xOf firmware/dl/GPL_*/GPL_*.zip | tar -xz -C firmware/gpl
# F2 binary check:
r2 -q -c 'aaa; s `/ Accept-Language:~[0]`; axt' firmware/x/376A/rootfs/usr/sbin/httpd   # -> main @0x4052d8
r2 -q -c 'aaa; s 0x4052d8; pd 22' firmware/x/376A/rootfs/usr/sbin/httpd                 # strcpy
r2 -q -c 'aaa; s 0x406724; pd 40' firmware/x/380A/rootfs/usr/sbin/httpd                 # strncpy 0xff
```
