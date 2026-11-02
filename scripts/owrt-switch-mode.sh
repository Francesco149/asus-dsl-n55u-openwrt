#!/bin/sh
# Turn an OpenWrt DSL-N55U into a cascaded L2 switch + backup AP (run ON the router):
#   scripts/owrt.sh 'sh -s' < scripts/owrt-switch-mode.sh
# - LAN gets its management IP from the upstream router via DHCP (hostname dsl-n55u)
# - static 192.168.1.1/24 stays on br-lan as a fallback management address ("mgmt")
# - no DHCP server, no IPv6 RA/DHCPv6/NDP, ULA prefix removed, odhcpd disabled (no rogue services on the main LAN)
# - Wi-Fi channels below, 20 MHz. The defaults suit an upstream AP on ch 7 and ch 36-48 (80 MHz); pick yours after a
#   survey (`iwinfo phy0-ap0 scan`, `iwinfo phy1-ap0 freqlist`). The rt2800 driver has no radar detection (DFS), so the
#   5 GHz AP is limited to 36-48 or the 5.8 GHz SRD band 149-173 (13 dBm under ETSI).
# Safety: config backed up to /tmp/rb and restored automatically after 180 s unless /tmp/net-confirmed exists.
CH2=1
CH5=149
set -e
FILES="network dhcp wireless firewall system"
mkdir -p /tmp/rb
for f in $FILES; do cp /etc/config/$f /tmp/rb/$f; done
rm -f /tmp/net-confirmed

setsid sh -c "sleep 180; [ -f /tmp/net-confirmed ] && exit 0; for f in $FILES; do cp /tmp/rb/\$f /etc/config/\$f; done; /etc/init.d/odhcpd enable; /etc/init.d/odhcpd start; /etc/init.d/system reload; /etc/init.d/network restart; wifi reload; logger -t switch-mode 'NOT CONFIRMED: ROLLED BACK'" </dev/null >/dev/null 2>&1 &

uci batch <<EOF
set system.@system[0].hostname='dsl-n55u'
set network.lan.proto='dhcp'
delete network.lan.ipaddr
delete network.lan.ip6assign
delete network.globals.ula_prefix
set network.mgmt=interface
set network.mgmt.device='br-lan'
set network.mgmt.proto='static'
set network.mgmt.ipaddr='192.168.1.1/24'
add_list firewall.@zone[0].network='mgmt'
set dhcp.lan.ignore='1'
set dhcp.lan.dhcpv6='disabled'
set dhcp.lan.ra='disabled'
set dhcp.lan.ndp='disabled'
set wireless.radio0.channel='$CH2'
set wireless.radio0.htmode='HT20'
set wireless.radio1.channel='$CH5'
set wireless.radio1.htmode='HT20'
EOF
uci commit
/etc/init.d/odhcpd stop || true
/etc/init.d/odhcpd disable || true
echo "applied; reloading in background (rollback armed for 180 s)"
setsid sh -c 'sleep 2; /etc/init.d/system reload; /etc/init.d/network reload; /etc/init.d/firewall reload; /etc/init.d/dnsmasq reload; wifi reload' </dev/null >/dev/null 2>&1 &
