# PowerShell Cloud-Init Generator (Pro Edition)
$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."
$CONFIG_FILE = "$ROOT_DIR\automation\config.yaml"
$TEMPLATE_ADGUARD = "$ROOT_DIR\automation\templates\AdGuardHome.yaml"
$OUTPUT_FILE = "$ROOT_DIR\final_cloud_init.yaml"

# Simplified Config Reader
function Get-ConfigValue {
    param ([string]$Section, [string]$Key)
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match "^\w+\s*:") {
            $inSection = $false
        }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*[`"']?([^`"']+)`?['`"]?") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Get-ConfigList {
    param ([string]$Section, [string]$Key)
    $list = @()
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    $inList = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match "^\w+\s*:") {
            $inSection = $false
        }
        if ($inSection -and $line -match "^\s+$Key\s*:") {
            $inList = $true
            continue
        }
        if ($inList -and $line -match "^\s+-\s*[`"']?([^`"']+)`?['`"]?") {
            $list += $Matches[1].Trim()
        } elseif ($inList -and $line -match "^\s+\w+\s*:") {
            $inList = $false
        }
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

# 3. Prepare AdGuard Template
if (-not (Test-Path $TEMPLATE_ADGUARD)) { Write-Error "Template not found!" }
$agTemplate = Get-Content -Path $TEMPLATE_ADGUARD -Raw
$agTemplate = $agTemplate.Replace("{{ADGUARD_USER}}", $ag_user)
$agTemplate = $agTemplate.Replace("{{ADGUARD_PASS_HASH}}", "ADGUARD_HASH_PLACEHOLDER")
$dnsBlock = ""; foreach ($dns in $ag_upstream) { $dnsBlock += "    - $dns`n" }
$agTemplate = $agTemplate.Replace("{{UPSTREAM_DNS_BLOCK}}", $dnsBlock.TrimEnd())
$filterBlock = ""; $c = 1; foreach ($url in $ag_blocklists) { $filterBlock += "  - enabled: true`n    url: $url`n    name: List $c`n    id: $c`n"; $c++ }
$agTemplate = $agTemplate.Replace("{{BLOCKLISTS_BLOCK}}", $filterBlock.TrimEnd())
$indentedAg = ""; foreach ($line in ($agTemplate -split "`r?`n")) { $indentedAg += "      $line`n" }

# 4. Define Template
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
      filter = sshd
      logpath = /var/log/auth.log
      maxretry = 3
      bantime = 1h

  - path: /root/adguard/conf/AdGuardHome.yaml
    permissions: "0644"
    content: |
{{ADGUARD_CONTENT}}
  - path: /root/Caddyfile
    content: |
      {
        email admin@sslip.io
        servers { protocols h1 h2 h3 }
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
        reverse_proxy adguardhome:8080 { header_up Host {upstream_hostport} }
      }
      vpn.DOMAIN_PLACEHOLDER {
        import security_headers
        reverse_proxy wg-easy:51821
      }

  - path: /root/docker-compose.yml
    content: |
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
            - PASSWORD_HASH=VPN_HASH_PLACEHOLDER
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

  - path: /root/setup.sh
    permissions: "0700"
    content: |
      #!/bin/bash
      VPN_PASS="{{VPN_PASS}}"
      AG_PASS="{{AG_PASS}}"
      VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
      AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)
      ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed "s/\\$/\\$\\/g")
      sed -i "s|VPN_HASH_PLACEHOLDER|$ESCAPED_VPN_HASH|g" /root/docker-compose.yml
      sed -i "s|ADGUARD_HASH_PLACEHOLDER|$AG_HASH|g" /root/adguard/conf/AdGuardHome.yaml
      sed -i "s|session_ttl: 0s|session_ttl: 720h|g" /root/adguard/conf/AdGuardHome.yaml
      cat <<EOF > /etc/sysctl.d/99-hardened.conf
      net.ipv4.conf.all.rp_filter = 1
      net.ipv4.conf.default.rp_filter = 1
      net.ipv4.icmp_echo_ignore_broadcasts = 1
      net.ipv4.conf.all.accept_source_route = 0
      net.ipv4.conf.default.accept_source_route = 0
      net.ipv4.tcp_syncookies = 1
      EOF
      sysctl -p /etc/sysctl.d/99-hardened.conf
      ipset create allowed_country hash:net
      URL="http://www.ipdeny.com/ipblocks/data/countries/{{COUNTRY}}.zone"
      curl -s $URL | while read line; do ipset add allowed_country $line; done
      ufw default deny incoming
      ufw allow ssh
      ufw insert 1 allow from set:allowed_country to any port 51820 proto udp
      ufw insert 1 allow from set:allowed_country to any port 80 proto tcp
      ufw insert 1 allow from set:allowed_country to any port 443 proto tcp
      echo "y" | ufw enable
      systemctl enable --now docker fail2ban unattended-upgrades
      cd /root && docker compose up -d

runcmd:
  - bash /root/setup.sh
'

# 5. Fill Template
$finalContent = $template.Replace("{{ADGUARD_CONTENT}}", $indentedAg)
$finalContent = $finalContent.Replace("{{VPN_PASS}}", $vpnPassword)
$finalContent = $finalContent.Replace("{{AG_PASS}}", $agPassword)
$finalContent = $finalContent.Replace("{{COUNTRY}}", $country.ToLower())

# Write to file
[System.IO.File]::WriteAllText($OUTPUT_FILE, $finalContent, [System.Text.Encoding]::ASCII)
Write-Host "SUCCESS: Professional config '$OUTPUT_FILE' created." -ForegroundColor Green