# Configuration Generator - Ultimate Precision Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
$ag_user = $config.adguard.username

# 2. Handle Passwords (Improved Array Input)
if ($MyInvocation.ExpectingInput) {
    $inputData = @($input)
    $vpnPassword = $inputData[0]; $agPassword = $inputData[1]
} else {
    $vpnPassword = Read-Host "  VPN UI Password"; $agPassword = Read-Host "  AdGuard UI Password"
}
if (!$vpnPassword) { $vpnPassword = "password" }
if (!$agPassword) { $agPassword = "password" }

# 3. Define the Bash Setup Script (Indented for YAML)
$bashScript = @'
#!/bin/bash
set -e

# 0. RAM Optimization (Swap File)
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# 1. Generate Hashes
VPN_PASS="{{VPN_PASS}}"
AG_PASS="{{AG_PASS}}"

# Generate proper hashes
VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)
ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed 's/\$/\$\$/g')

# 2. Create AdGuard Config via Template
mkdir -p /root/adguard/conf
cat <<'EOF' > /tmp/ag_template.yaml
http:
  address: 0.0.0.0:8080
  session_ttl: 720h
users:
  - name: "AG_USER_PLACEHOLDER"
    password: "AG_HASH_PLACEHOLDER"
dns:
  bind_hosts: ["0.0.0.0"]
  port: 53
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "tls://1.1.1.1"]
filtering_enabled: true
protection_enabled: true
setup_done: true
EOF

sed "s|AG_USER_PLACEHOLDER|{{AG_USER}}|g" /tmp/ag_template.yaml > /tmp/ag_step1.yaml
sed "s|AG_HASH_PLACEHOLDER|$AG_HASH|g" /tmp/ag_step1.yaml > /root/adguard/conf/AdGuardHome.yaml

# 3. Create Caddyfile
cat <<'EOF' > /root/Caddyfile
{
  email admin@sslip.io
}
adguard.DOMAIN_PLACEHOLDER {
  tls internal
  reverse_proxy adguardhome:8080 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
vpn.DOMAIN_PLACEHOLDER {
  tls internal
  reverse_proxy wg-easy:51821
}
EOF

# 4. Create Docker Compose via Template
cat <<'EOF' > /tmp/dc_template.yml
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
      - PASSWORD_HASH=VPN_HASH_PLACEHOLDER
      - WG_DEFAULT_DNS=172.20.0.53
      - WG_ALLOWED_IPS=0.0.0.0/0, ::/0
      - WG_MTU=1420
      - WG_PERSISTENT_KEEPALIVE=25
    volumes: ["./wg-easy:/etc/wireguard"]
    ports: ["51820:51820/udp"]
    expose: ["51821"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1
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

sed "s|VPN_HASH_PLACEHOLDER|$ESCAPED_VPN_HASH|g" /tmp/dc_template.yml > /root/docker-compose.yml

# 5. Kernel Hardening
cat <<EOF > /etc/sysctl.d/99-hardened.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
EOF
sysctl -p /etc/sysctl.d/99-hardened.conf

# 6. Firewall
ufw default deny incoming
ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 51820/udp
echo "y" | ufw enable
systemctl enable --now docker fail2ban unattended-upgrades
cd /root && docker compose up -d
'@

# Replace Password Placeholders in the script template
$finalBash = $bashScript.Replace("{{VPN_PASS}}", $vpnPassword).Replace("{{AG_PASS}}", $agPassword).Replace("{{AG_USER}}", $ag_user)

# Format for YAML (Indent 6 spaces)
$indentedBash = ""
foreach ($line in ($finalBash -split "`n")) { $indentedBash += "      $line`n" }

# Final YAML Construct
$finalYaml = @"
#cloud-config
package_update: true
package_upgrade: true
packages: [docker.io, docker-compose-v2, curl, ufw, apache2-utils, fail2ban, unattended-upgrades]

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
$indentedBash
runcmd:
  - bash /root/setup.sh
"@

$outputPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
[System.IO.File]::WriteAllText($outputPath, $finalYaml, [System.Text.Encoding]::ASCII)
Show-Success "Precision Automated configuration generated."