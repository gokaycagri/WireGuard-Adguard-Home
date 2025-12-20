# PowerShell Cloud-Init Generator (Pro Edition - Robust Passwords)
$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."
$CONFIG_FILE = "$ROOT_DIR\automation\config.yaml"
$TEMPLATE_ADGUARD = "$ROOT_DIR\automation\templates\AdGuardHome.yaml"
$OUTPUT_FILE = "$ROOT_DIR\final_cloud_init.yaml"

# --- Functions ---
function Get-ConfigValue {
    param ([string]$Section, [string]$Key)
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") { $inSection = $true; continue }
        if ($inSection -and $line -match "^\w+\s*:") { $inSection = $false }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*[`"']?([^`"']+)`?['`"]?") { return $Matches[1].Trim() }
    }
    return $null
}

function Get-ConfigList {
    param ([string]$Section, [string]$Key)
    $list = @(); $lines = Get-Content $CONFIG_FILE; $inSection = $false; $inList = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") { $inSection = $true; continue }
        if ($inSection -and $line -match "^\w+\s*:") { $inSection = $false }
        if ($inSection -and $line -match "^\s+$Key\s*:") { $inList = $true; continue }
        if ($inList -and $line -match "^\s+-\s*[`"']?([^`"']+)`?['`"]?") { $list += $Matches[1].Trim() }
        elseif ($inList -and $line -match "^\s+\w+\s*:") { $inList = $false }
    }
    return $list
}

Write-Host "--- Professional VPN Configuration Generator ---" -ForegroundColor Cyan

# 1. Load Settings
if (-not (Test-Path $CONFIG_FILE)) { Write-Error "Config file not found!" }
$ag_user = Get-ConfigValue -Section "adguard" -Key "username"
$ag_upstream = Get-ConfigList -Section "adguard" -Key "upstream_dns"
$ag_blocklists = Get-ConfigList -Section "adguard" -Key "blocklists"
$country = Get-ConfigValue -Section "azure" -Key "allowed_country"

# 2. Handle Passwords
if ($MyInvocation.ExpectingInput) {
    $inputData = $input | Where-Object { $_ }
    $vpnPassword = $inputData[0]
    $agPassword = $inputData[1]
} else {
    $vpnPassword = Read-Host "Enter the password for WireGuard (VPN) UI"
    $agPassword = Read-Host "Enter the password for AdGuard Home UI"
}
if ([string]::IsNullOrWhiteSpace($vpnPassword)) { $vpnPassword = "password" }
if ([string]::IsNullOrWhiteSpace($agPassword)) { $agPassword = "password" }

# 3. Prepare Blocks
$dnsBlock = ""; foreach ($dns in $ag_upstream) { $dnsBlock += "    - $dns`n" }
$filterBlock = ""; $c = 1; foreach ($url in $ag_blocklists) { $filterBlock += "  - enabled: true`n    url: $url`n    name: List $c`n    id: $c`n"; $c++ }

# 4. Final Cloud-Init Template
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
      # 1. Generate Hashes
      VPN_PASS="{{VPN_PASS}}"
      AG_PASS="{{AG_PASS}}"
      
      # Generate high-compatibility Bcrypt hashes
      VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
      AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)
      ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed "s/\$\/\$\$\$/g")

      # 2. Create AdGuard Config
      mkdir -p /root/adguard/conf
      cat <<EOF > /root/adguard/conf/AdGuardHome.yaml
      bind_host: 0.0.0.0
      bind_port: 8080
      users:
        - name: {{AG_USER}}
          password: $AG_HASH
      dns:
        bind_hosts: [0.0.0.0]
        port: 53
        upstream_dns:
      {{UPSTREAM_DNS}}
        protection_enabled: true
        filtering_enabled: true
        blocking_mode: default
      filters:
      {{BLOCKLISTS}}
      setup_done: true
      http:
        session_ttl: 720h
      EOF

      # 3. Create Caddyfile
      cat <<EOF > /root/Caddyfile
      {
        email admin@sslip.io
      }
      (security_headers) {
        header {
          Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
          X-XSS-Protection "1; mode=block"
          X-Content-Type-Options "nosniff"
          X-Frame-Options "DENY"
          Referrer-Policy "strict-origin-when-cross-origin"
        }
      }
      adguard.DOMAIN_PLACEHOLDER {
        import security_headers
        reverse_proxy adguardhome:8080 {
          header_up Host {upstream_hostport}
        }
      }
      vpn.DOMAIN_PLACEHOLDER {
        import security_headers
        reverse_proxy wg-easy:51821
      }
      EOF

      # 4. Create Docker Compose
      cat <<EOF > /root/docker-compose.yml
      services:
        caddy:
          image: caddy:latest
          container_name: caddy
          restart: unless-stopped
          ports: ["80:80", "443:443", "443:443/udp"]
          volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "./caddy_data:/data", "./caddy_config:/config"]
          mem_limit: 256m
        wg-easy:
          image: ghcr.io/wg-easy/wg-easy
          container_name: wg-easy
          environment:
            - WG_HOST=auto
            - PASSWORD_HASH=$ESCAPED_VPN_HASH
            - WG_DEFAULT_DNS=172.20.0.53
            - WG_ALLOWED_IPS=0.0.0.0/0, ::/0
          volumes: ["./wg-easy:/etc/wireguard"]
          ports: ["51820:51820/udp"]
          expose: ["51821"]
          restart: unless-stopped
          cap_add: [NET_ADMIN, SYS_MODULE]
          sysctls: { "net.ipv4.ip_forward": 1, "net.ipv4.conf.all.src_valid_mark": 1 }
          mem_limit: 512m
        adguardhome:
          image: adguard/adguardhome
          container_name: adguardhome
          restart: unless-stopped
          volumes: ["./adguard/work:/opt/adguardhome/work", "./adguard/conf:/opt/adguardhome/conf"]
          ports: ["3000:3000/tcp"]
          expose: ["8080"]
          networks:
            default: { ipv4_address: 172.20.0.53 }
          mem_limit: 512m
        watchtower:
          image: containrrr/watchtower
          container_name: watchtower
          restart: unless-stopped
          volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
          command: --cleanup --interval 86400
          mem_limit: 128m
      networks:
        default:
          ipam:
            config: [{ subnet: 172.20.0.0/24 }]
      EOF

      # 5. Geo-Blocking & Firewall
      ipset create allowed_country hash:net
      URL="http://www.ipdeny.com/ipblocks/data/countries/{{COUNTRY}}.zone"
      curl -s $URL | while read line; do ipset add allowed_country $line; done
      ufw default deny incoming
      ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp
      ufw insert 1 allow from set:allowed_country to any port 51820 proto udp
      echo "y" | ufw enable

      # 6. Launch
      systemctl enable --now docker fail2ban unattended-upgrades
      cd /root && docker compose up -d

runcmd:
  - bash /root/setup.sh
'

# 5. Fill Template
$finalContent = $template.Replace("{{VPN_PASS}}", $vpnPassword)
$finalContent = $finalContent.Replace("{{AG_PASS}}", $agPassword)
$finalContent = $finalContent.Replace("{{AG_USER}}", $ag_user)
$finalContent = $finalContent.Replace("{{COUNTRY}}", $country.ToLower())
$finalContent = $finalContent.Replace("{{UPSTREAM_DNS}}", $dnsBlock.TrimEnd())
$finalContent = $finalContent.Replace("{{BLOCKLISTS}}", $filterBlock.TrimEnd())

# Write to file
[System.IO.File]::WriteAllText($OUTPUT_FILE, $finalContent, [System.Text.Encoding]::ASCII)
Write-Host "SUCCESS: Robust Professional config '$OUTPUT_FILE' created." -ForegroundColor Green
