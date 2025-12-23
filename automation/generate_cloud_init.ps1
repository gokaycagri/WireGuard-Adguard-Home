# Configuration Generator - Ultimate Bulletproof Edition (Fixed Variable Name)
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\lib.ps1"

# 1. Load Data
$Config = Get-VpnConfig
$AgUser = $Config.adguard.username

# 2. Handle Passwords & Options
if ($MyInvocation.ExpectingInput) {
    $inputData = @($input | Where-Object { $_ -ne $null })
    $VpnPass = $inputData[0].Trim()
    $AgPass = $inputData[1].Trim()
    if ($inputData.Count -gt 2) { $InitialWgUser = $inputData[2].Trim() } else { $InitialWgUser = "" }
} else {
    $VpnPass = (Read-Host "  VPN UI Password").Trim()
    $AgPass = (Read-Host "  Dashboard Password").Trim()
    $InitialWgUser = ""
}

$VpnB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($VpnPass))
$AgB64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($AgPass))

# 3. Final Bash Setup Script
$bashScript = @'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# 0. Fix Hostname
echo "127.0.0.1 $(hostname)" >> /etc/hosts
sleep 10

# 1. Install Packages (Force reliable install)
apt-get update
apt-get install -y docker.io docker-compose-v2 curl ufw apache2-utils fail2ban unattended-upgrades jq

# 2. RAM Optimization
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
fi

# 3. Decode Passwords
VPN_PASS=$(echo "{{VPN_B64}}" | base64 -d)
AG_PASS=$(echo "{{AG_B64}}" | base64 -d)

# 4. Generate Hashes (Using pure bash to avoid shell expansion issues)
VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed 's/\$/\$\$/g')
AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)

# 5. Create AdGuard Config (MOST STABLE YAML FORMAT)
mkdir -p /root/adguard/conf /root/adguard/work
cat <<EOF > /root/adguard/conf/AdGuardHome.yaml
http:
  address: 0.0.0.0:8080
  session_ttl: 720h
users:
  - name: "{{AG_USER}}"
    password: "$AG_HASH"
dns:
  bind_hosts:
    - 0.0.0.0
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
setup_done: true
schema_version: 32
EOF

# 6. Create Caddyfile
# Placeholder for Auth - will be filled by Caddy tool
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

# Inject Caddy Hash
CADDY_HASH=$(docker run --rm caddy:latest caddy hash-password --plaintext "$AG_PASS")
sed -i "s|CADDY_HASH_PLACEHOLDER|$CADDY_HASH|g" /root/Caddyfile

# 7. Create Docker Compose (Using Double $$ for all variable hashes)
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
      - WG_HOST=$(curl -s https://api.ipify.org)
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
    container_name: watchtower
    volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
    command: --cleanup --interval 86400
    restart: unless-stopped
networks:
  default:
    ipam:
      config: [{ subnet: 172.20.0.0/24 }]
EOF

# 8. DNS Fix
systemctl stop systemd-resolved || true
systemctl disable systemd-resolved || true
rm -f /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

# 9. Routing & NAT
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i wg0 -o docker0 -j ACCEPT
iptables -A FORWARD -i docker0 -o wg0 -j ACCEPT

# 10. Firewall
ufw default deny incoming
ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 51820/udp; ufw allow 53/udp; ufw allow 53/tcp
ufw allow in on wg0
echo "y" | ufw enable

# 11. Launch
cd /root && docker compose up -d

# 12. Auto-Create Initial WireGuard User (Optional)
INITIAL_USER="{{INITIAL_WG_USER}}"
if [ -n "$INITIAL_USER" ]; then
    echo "Waiting for WireGuard API to initialize..."
    # Wait max 60 seconds for port 51821
    for i in {1..12}; do
        if curl -s http://172.20.0.6:51821/api/session > /dev/null; then break; fi
        sleep 5
    done
    
    echo "Creating initial user: $INITIAL_USER"
    COOKIE="/tmp/wg_init_cookie"
    # Authenticate
    curl -s -c $COOKIE -H "Content-Type: application/json" -d "{\"password\":\"$VPN_PASS\"}" http://172.20.0.6:51821/api/session
    # Create User
    curl -s -b $COOKIE -H "Content-Type: application/json" -d "{\"name\":\"$INITIAL_USER\"}" http://172.20.0.6:51821/api/wireguard/client
    rm -f $COOKIE
fi
'@

# 4. Inject Data & Write
$Final = $bashScript.Replace("{{VPN_PASS_RAW}}", $VpnPass).Replace("{{AG_PASS_RAW}}", $AgPass).Replace("{{AG_USER}}", $AgUser).Replace("{{VPN_B64}}", $VpnB64).Replace("{{AG_B64}}", $AgB64).Replace("{{INITIAL_WG_USER}}", $InitialWgUser)

# Robust Indentation (6 spaces)
$IndentedBash = ""
foreach ($Line in ($Final -split "`n")) { 
    if ($Line.Trim().Length -gt 0) { $IndentedBash += "      $Line`n" } else { $IndentedBash += "`n" }
}

$FinalYaml = @"
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
$IndentedBash
runcmd:
  - bash /root/setup.sh
"@

$OutputPath = Join-Path $ScriptDir "..\final_cloud_init.yaml"
[System.IO.File]::WriteAllText($OutputPath, $FinalYaml, [System.Text.Encoding]::ASCII)
Show-Success "Bulletproof configuration generated."