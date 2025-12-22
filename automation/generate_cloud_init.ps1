# Configuration Generator - Final Robust Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
$ag_user = $config.adguard.username

# 2. Handle Passwords (Improved Array Input)
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

# 3. Final Cloud-Init Template
# Note: Indentation here is for the internal Bash script. 
# We will wrap this in the YAML structure with proper indentation later.
$bashScript = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# 0. Fix Hostname and Wait for Net
echo "127.0.0.1 $(hostname)" >> /etc/hosts
sleep 15

# 1. Install Packages
apt-get update
apt-get install -y docker.io docker-compose-v2 curl ufw apache2-utils fail2ban unattended-upgrades

# 2. RAM Optimization
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# 3. Decode Passwords & Detect IP
VPN_PASS=$(echo "{{VPN_B64}}" | base64 -d)
AG_PASS=$(echo "{{AG_B64}}" | base64 -d)
PUB_IP=$(curl -s https://api.ipify.org || echo "auto")

# 4. Generate Hashes
command -v htpasswd >/dev/null 2>&1 || (apt-get update && apt-get install -y apache2-utils)
VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed 's/\$/\$\$/g')
AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)

# Generate Caddy Auth Hash
systemctl start docker
CADDY_HASH=$(docker run --rm caddy:latest caddy hash-password --plaintext "$AG_PASS")

# 5. Create AdGuard Config
mkdir -p /root/adguard/conf /root/adguard/work
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
  protection_enabled: true
  filtering_enabled: true
filtering:
  rewrites:
    - domain: "adguard.DOMAIN_PLACEHOLDER"
      answer: "10.8.0.1"
      enabled: true
    - domain: "vpn.DOMAIN_PLACEHOLDER"
      answer: "10.8.0.1"
      enabled: true
    - domain: "speed.DOMAIN_PLACEHOLDER"
      answer: "10.8.0.1"
      enabled: true
    - domain: "glances.DOMAIN_PLACEHOLDER"
      answer: "10.8.0.1"
      enabled: true
schema_version: 14
EOF

# 6. Create Caddyfile
cat <<'EOF' > /root/Caddyfile
{
  email admin@sslip.io
}
adguard.DOMAIN_PLACEHOLDER {
  reverse_proxy 172.20.0.53:8080 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}
vpn.DOMAIN_PLACEHOLDER {
  reverse_proxy 172.20.0.6:51821
}
speed.DOMAIN_PLACEHOLDER {
  basic_auth {
    {{AG_USER}} CADDY_HASH_PLACEHOLDER
  }
  reverse_proxy 172.20.0.4:3000
}
glances.DOMAIN_PLACEHOLDER {
  basic_auth {
    {{AG_USER}} CADDY_HASH_PLACEHOLDER
  }
  reverse_proxy 172.20.0.5:61208
}
EOF

sed -i "s|CADDY_HASH_PLACEHOLDER|$CADDY_HASH|g" /root/Caddyfile

# 7. Create Docker Compose
cat <<EOF > /root/docker-compose.yml
services:
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports: ["80:80", "443:443", "443:443/udp"]
    volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "./caddy_data:/data"]
    networks: { default: { ipv4_address: 172.20.0.3 } }
  wg-easy:
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    restart: unless-stopped
    environment:
      - WG_HOST=$PUB_IP
      - PASSWORD_HASH=$ESCAPED_VPN_HASH
      - WG_DEFAULT_DNS=172.20.0.53
      - WG_ALLOWED_IPS=0.0.0.0/0, ::/0
      - WG_MTU=1420
      - WG_PERSISTENT_KEEPALIVE=25
    volumes: ["./wg-easy:/etc/wireguard"]
    ports: ["51820:51820/udp"]
    cap_add: [NET_ADMIN, SYS_MODULE]
    sysctls: { net.ipv4.ip_forward: 1 }
    networks: { default: { ipv4_address: 172.20.0.6 } }
  adguardhome:
    image: adguard/adguardhome
    container_name: adguardhome
    restart: unless-stopped
    volumes: ["./adguard/work:/opt/adguardhome/work", "./adguard/conf:/opt/adguardhome/conf"]
    ports: ["53:53/udp", "53:53/tcp"]
    networks: { default: { ipv4_address: 172.20.0.53 } }
  speedtest:
    image: openspeedtest/latest
    container_name: speedtest
    restart: unless-stopped
    expose: ["3000"]
    networks: { default: { ipv4_address: 172.20.0.4 } }
  glances:
    image: nicolargo/glances:latest
    container_name: glances
    restart: unless-stopped
    pid: host
    environment: [GLANCES_OPT=-w]
    volumes: ["/var/run/docker.sock:/var/run/docker.sock:ro"]
    expose: ["61208"]
    networks: { default: { ipv4_address: 172.20.0.5 } }
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

# 8. Routing & NAT
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i wg0 -o docker0 -j ACCEPT
iptables -A FORWARD -i docker0 -o wg0 -j ACCEPT

# 9. DNS Fix
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# 10. Firewall
ufw default deny incoming
ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 51820/udp; ufw allow 53/udp; ufw allow 53/tcp
ufw allow in on wg0
echo "y" | ufw enable

# 11. Launch
cd /root && docker compose up -d
'@

# Replace placeholders in the bash script
$bashContent = $bashScript.Replace("{{VPN_B64}}", $vpnBase64).Replace("{{AG_B64}}", $agBase64).Replace("{{AG_USER}}", $ag_user)

# Format for YAML inclusion (Indent EVERY line by 6 spaces)
$indentedBash = ""
foreach ($line in ($bashContent -split "`n")) {
    $indentedBash += "      $line`n"
}

# 4. Construct Final Cloud-Init YAML
$finalYaml = @"
#cloud-config
package_update: true
package_upgrade: false

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

# Write to file
$outputPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
[System.IO.File]::WriteAllText($outputPath, $finalYaml, [System.Text.Encoding]::ASCII)
Show-Success "Final Stable configuration generated with correct indentation."
