{
  description = "ASUS DSL-N55U research environment (recon, firmware analysis, emulation)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      devShells = forAll (pkgs:
        let
          py = pkgs.python3.withPackages (ps: with ps; [
            requests
            scapy
            pycryptodome
            beautifulsoup4
          ]);
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              # network recon / interaction
              nmap
              tcpdump
              arp-scan
              netcat-openbsd
              socat
              inetutils # telnet, ftp
              curl
              wget
              openssl
              openssh
              sshpass
              net-snmp # snmpwalk
              miniupnpc # upnpc
              tftp-hpa # ASUS rescue-mode firmware upload
              dig
              dnsmasq # fake-ISP DHCP/DNS on the router's WAN side
              iproute2

              # firmware unpacking / analysis
              binwalk
              squashfsTools
              sasquatch # squashfs w/ vendor LZMA variants
              file
              xxd
              hexyl
              ripgrep
              radare2
              binutils
              xz
              zstd

              # emulation of MIPS userland
              qemu

              # serial console (UART)
              picocom

              py
            ];

            shellHook = ''
              export DSL_LAN_IF=''${DSL_LAN_IF:-enp3s0}
              export DSL_HOST=''${DSL_HOST:-192.168.1.1}
              echo "dsl-n55u devshell: iface=$DSL_LAN_IF target=$DSL_HOST"
              echo "raw-socket tools need root: sudo \$(command -v tcpdump) ..."
            '';
          };
        });
    };
}
