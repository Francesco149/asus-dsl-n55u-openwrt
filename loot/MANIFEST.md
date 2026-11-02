# loot/ manifest

Pages fetched from the **stock** ASUS web UI (firmware 3.0.0.4.376_2736) during the review. They are ASUS's code and
device-generated content, so **the files themselves are not published**. They stay local (gitignored). This manifest
records what was fetched and their hashes, so the observations in `docs/02-stock-firmware.md` (F6, F7) can be checked
against a re-capture (hashes are of the stored copies after MAC redaction). `live/sysinfo.txt` (our command output on the device) is included.

| File | Request | Credentials | HTTP | Bytes | SHA-256 | Note |
|---|---|---|---|---|---|---|
| `error_page.htm` | `GET /error_page.htm` | none | 200 | 12468 | `ebba9ce521815001…` | pre-reset AP-mode unit; unauthenticated, shows LAN IP/netmask (F7) |
| `index-default.asp` | `GET /index.asp` | admin/admin | 200 | 43653 | `06ffb7cecfeefb08…` | factory-default unit, authenticated |
| `noauth/Advanced_System_Content.asp` | `GET /Advanced_System_Content.asp` | none | 200 | 41114 | `647a43d3c976dca9…` | fetched without credentials on the factory-default unit after `skip_auth` was latched (F6) |
| `noauth/Nologin.asp` | `GET /Nologin.asp` | none | 200 | 1411 | `9b035bb804b1d315…` | fetched without credentials on the factory-default unit |
| `noauth/QIS_wizard.htm` | `GET /QIS_wizard.htm` | none | 200 | 7378 | `a639a6650380f98f…` | fetched without credentials on the factory-default unit |
| `noauth/WAN_info.asp` | `GET /WAN_info.asp` | none | 200 | 71 | `042d471ae809ee54…` | fetched without credentials on the factory-default unit |
| `noauth/automac.asp` | `GET /automac.asp` | none | 200 | 5 | `e3a7c95d7ca43812…` | fetched without credentials on the factory-default unit |
| `noauth/blocking.asp` | `GET /blocking.asp` | none | 404 | 126 | `476cf2a700cc8e5c…` | fetched without credentials on the factory-default unit |
| `noauth/detect_firmware.asp` | `GET /detect_firmware.asp` | none | 200 | 98 | `7cd1e721b8834c62…` | fetched without credentials on the factory-default unit |
| `noauth/httpd_check.htm` | `GET /httpd_check.htm` | none | 200 | 72 | `00638065830448eb…` | fetched without credentials on the factory-default unit |
| `noauth/index.asp` | `GET /index.asp` | none | 200 | 43653 | `06ffb7cecfeefb08…` | fetched without credentials on the factory-default unit after `skip_auth` was latched (F6) |
| `noauth/result_of_get_changed_status_QIS.asp` | `GET /result_of_get_changed_status_QIS.asp` | none | 200 | 930 | `a43ac314d98b1fbd…` | fetched without credentials on the factory-default unit |
| `noauth/status.asp` | `GET /status.asp` | none | 200 | 1703 | `973c13db4790a1c7…` | fetched without credentials on the factory-default unit |
| `noauth/update_applist.asp` | `GET /update_applist.asp` | none | 200 | 42 | `c7fc7ab281c7a747…` | fetched without credentials on the factory-default unit |
| `noauth/update_appstate.asp` | `GET /update_appstate.asp` | none | 200 | 354 | `e06f3ae1158486c1…` | fetched without credentials on the factory-default unit |
| `noauth/update_cloudstatus.asp` | `GET /update_cloudstatus.asp` | none | 200 | 70 | `0d8071a336b474be…` | fetched without credentials on the factory-default unit |
| `state-default.js` | `GET /state.js` | admin/admin | 200 | 113505 | `22278bb095a581f4…` | authenticated copy |
| `state-noauth.js` | `GET /state.js` | none | 200 | 113505 | `e078d762cb9c7d87…` | unauthenticated; identical to the authenticated copy except uptime (F7) |
