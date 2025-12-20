# Configuration Generator - Robust Formatting
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
$ag_user = $config.adguard.username
$country = $config.azure.allowed_country

# 2. Handle Passwords
if ($MyInvocation.ExpectingInput) {
    $inputData = $input | Where-Object { $_ }
    $vpnPassword = $inputData[0]; $agPassword = $inputData[1]
} else {
    $vpnPassword = Read-Host "  VPN UI Password"; $agPassword = Read-Host "  AdGuard UI Password"
}
if (!$vpnPassword) { $vpnPassword = "password" }
if (!$agPassword) { $agPassword = "password" }

# 3. Build Template (No leading spaces inside EOF blocks)
$template = '#cloud-config
package_update: true
package_upgrade: true
packages: [docker.io, docker-compose-v2, curl, ufw, apache2-utils, fail2ban, unattended-upgrades, ipset]

write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      maxretry = 3
      bantime = 1h

  - path: /root/setup.sh
    permissions: "0700"
    content: |
      #!/bin/bash
      set -e
      # 1. Hashes
      VPN_HASH=$(htpasswd -B -n -b admin "{{VPN_PASS}}" | cut -d ":" -f 2)
      AG_HASH=$(htpasswd -B -n -b admin "{{AG_PASS}}" | cut -d ":" -f 2)
      ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed "s/\$/\$\$/g")

      # 2. Configs
      mkdir -p /root/adguard/conf
      cat <<EOF > /root/adguard/conf/AdGuardHome.yaml
bind_host: 0.0.0.0
bind_port: 8080
users:
  - name: "{{AG_USER}}"
    password: "$AG_HASH"
dns:
  bind_hosts: [0.0.0.0]
  port: 53
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "tls://1.1.1.1"]
  protection_enabled: true
setup_done: true
http:
  session_ttl: 720h
EOF

      cat <<EOF > /root/Caddyfile
{ email admin@sslip.io }
adguard.DOMAIN_PLACEHOLDER {
  reverse_proxy adguardhome:8080 {
    header_up Host {upstream_hostport}
  }
}
vpn.DOMAIN_PLACEHOLDER {
  reverse_proxy wg-easy:51821
}
EOF

      cat <<EOF > /root/docker-compose.yml
services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "./caddy_data:/data"]
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    environment:
      - WG_HOST=auto
      - PASSWORD_HASH=$ESCAPED_VPN_HASH
      - WG_DEFAULT_DNS=172.20.0.53
      - WG_ALLOWED_IPS=0.0.0.0/0
    volumes: ["./wg-easy:/etc/wireguard"]
    ports: ["51820:51820/udp"]
    expose: ["51821"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
  adguardhome:
    image: adguard/adguardhome
    container_name: adguardhome
    volumes: ["./adguard/work:/opt/adguardhome/work", "./adguard/conf:/opt/adguardhome/conf"]
    expose: ["8080"]
    networks:
      default:
        ipv4_address: 172.20.0.53
    restart: unless-stopped
  watchtower:
    image: containrrr/watchtower
    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
    command: --cleanup --interval 86400
    restart: unless-stopped
networks:
  default:
    ipam:
      config:
        - subnet: 172.20.0.0/24
EOF

      # 3. Firewall
      ipset create allowed_country hash:net
      URL="http://www.ipdeny.com/ipblocks/data/countries/{{COUNTRY}}.zone"
      curl -s $URL | while read line; do ipset add allowed_country $line; done
      ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp
      ufw insert 1 allow from set:allowed_country to any port 51820 proto udp
      echo "y" | ufw enable
      systemctl enable --now docker fail2ban unattended-upgrades
      cd /root && docker compose up -d

runcmd:
  - bash /root/setup.sh
'

# 4. Inject & Write
$final = $template.Replace("{{VPN_PASS}}", $vpnPassword).Replace("{{AG_PASS}}", $agPassword).Replace("{{AG_USER}}", $ag_user).Replace("{{COUNTRY}}", $country.ToLower())
$outputPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
[System.IO.File]::WriteAllText($outputPath, $final, [System.Text.Encoding]::ASCII)