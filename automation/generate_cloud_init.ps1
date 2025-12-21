# Configuration Generator - Ultimate Validated Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
$ag_user = $config.adguard.username

# 2. Handle Passwords (Cleaning up input)
if ($MyInvocation.ExpectingInput) {
    $inputData = @($input | Where-Object { $_ -ne $null })
    $vpnPassword = if ($inputData[0]) { $inputData[0].Trim() } else { "password" }
    $agPassword = if ($inputData[1]) { $inputData[1].Trim() } else { "password" }
} else {
    $vpnPassword = (Read-Host "  VPN UI Password").Trim()
    $agPassword = (Read-Host "  Dashboard Password").Trim()
}
if (!$vpnPassword) { $vpnPassword = "password" }
if (!$agPassword) { $agPassword = "password" }

$vpnBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($vpnPassword))
$agBase64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($agPassword))

# 3. Build Template (Literal Bash Script)
$bashScript = @'
#!/bin/bash
set -e

# 0. RAM Optimization
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# 1. Decode Passwords
VPN_PASS=$(echo "{{VPN_B64}}" | base64 -d)
AG_PASS=$(echo "{{AG_B64}}" | base64 -d)
PUB_IP=$(curl -s https://api.ipify.org || echo "auto")

# 2. Generate Hashes
sudo apt-get update && sudo apt-get install -y apache2-utils
VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed 's/\$/\$\$/g')
AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)

# 3. Create AdGuard Config
mkdir -p /root/adguard/conf
cat <<EOF > /root/adguard/conf/AdGuardHome.yaml
http:
  address: 0.0.0.0:8080
  session_ttl: 720h
users:
  - name: "{{AG_USER}}"
    password: "$AG_HASH"
dns:
  bind_hosts: ["0.0.0.0"]
  port: 53
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "tls://1.1.1.1"]
  bootstrap_dns: ["1.1.1.1", "8.8.8.8"]
  enable_dnssec: true
  ratelimit: 20
filtering_enabled: true
protection_enabled: true
setup_done: true
EOF

# 4. Create Caddyfile
cat <<'EOF' > /root/Caddyfile
{
  email admin@sslip.io
}
adguard.DOMAIN_PLACEHOLDER {
  reverse_proxy adguardhome:8080 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
  }
}
vpn.DOMAIN_PLACEHOLDER {
  reverse_proxy wg-easy:51821
}
speed.DOMAIN_PLACEHOLDER {
  basicauth {
    admin AG_HASH_PLACEHOLDER
  }
  reverse_proxy speedtest:3000
}
glances.DOMAIN_PLACEHOLDER {
  basicauth {
    admin AG_HASH_PLACEHOLDER
  }
  reverse_proxy glances:61208
}
EOF

sed -i "s|AG_HASH_PLACEHOLDER|$AG_HASH|g" /root/Caddyfile

# 5. Create Docker Compose
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
      - WG_HOST=$PUB_IP
      - PASSWORD_HASH=$ESCAPED_VPN_HASH
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
    ports: ["53:53/udp", "53:53/tcp"]
    networks:
      default:
        ipv4_address: 172.20.0.53
    restart: unless-stopped
  speedtest:
    image: openspeedtest/latest
    container_name: speedtest
    restart: unless-stopped
    expose: ["3000"]
  glances:
    image: nicolargo/glances:latest
    container_name: glances
    restart: unless-stopped
    pid: host
    environment: [GLANCES_OPT=-w]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock:ro"]
    expose: ["61208"]
  watchtower:
    image: containrrr/watchtower
    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
    command: --cleanup --interval 86400
    restart: unless-stopped
networks:
  default:
    ipam:
      config: [{ subnet: 172.20.0.0/24 }]
EOF

# 6. Kernel Hardening
cat <<EOF > /etc/sysctl.d/99-hardened.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
EOF
sysctl -p /etc/sysctl.d/99-hardened.conf

# 7. DNS & Firewall Fix
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

ufw default deny incoming
ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 51820/udp; ufw allow 53/udp; ufw allow 53/tcp
echo "y" | ufw enable

# 8. Launch
cd /root && docker compose up -d
'@

# Replace Password Placeholders
$bashContent = $bashScript.Replace("{{VPN_B64}}", $vpnBase64).Replace("{{AG_B64}}", $agBase64).Replace("{{AG_USER}}", $ag_user)

# Format for YAML (Indent 6 spaces)
$indentedBash = ""
foreach ($line in ($bashContent -split "`n")) { $indentedBash += "      $line`n" }

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
Show-Success "Automated Robust configuration generated."