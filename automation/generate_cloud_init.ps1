# PowerShell Cloud-Init Generator (Clean Code Edition)
$ErrorActionPreference = "Stop"

# --- Configuration Paths ---
$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."
$CONFIG_FILE = "$ROOT_DIR\automation\config.yaml"
$TEMPLATE_ADGUARD = "$ROOT_DIR\automation\templates\AdGuardHome.yaml"
$OUTPUT_FILE = "$ROOT_DIR\final_cloud_init.yaml"

# --- Functions ---

function Get-ConfigValue {
    param ([string]$Content, [string]$Section, [string]$Key)
    $pattern = '(?ms)^' + [regex]::Escape($Section) + ':\s*$(.+?)(?=^\w+:|\Z)'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        $secContent = $match.Groups[1].Value
        $keyPattern = '^\s+' + [regex]::Escape($Key) + ':\s*(.+)$'
        $keyMatch = [regex]::Match($secContent, $keyPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($keyMatch.Success) { return $keyMatch.Groups[1].Value.Trim().Trim("'").Trim("'") }
    }
    return $null
}

function Get-ConfigList {
    param ([string]$Content, [string]$Section, [string]$Key)
    $list = @()
    $pattern = '(?ms)^' + [regex]::Escape($Section) + ':\s*$(.+?)(?=^\w+:|\Z)'
    $match = [regex]::Match($Content, $pattern)
    if ($match.Success) {
        $secContent = $match.Groups[1].Value
        $listPattern = '(?ms)^\s+' + [regex]::Escape($Key) + ':\s*$(\s+-\s+[^\r\n]+[\r\n]*)+' 
        $listMatch = [regex]::Match($secContent, $listPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($listMatch.Success) {
            foreach ($line in ($listMatch.Value -split "`r?`n")) {
                if ($line -match '^\s+-\s+(.+)$') { $list += $Matches[1].Trim().Trim("'").Trim("'") }
            }
        }
    }
    return $list
}

Write-Host "--- VPN Configuration Generator ---" -ForegroundColor Cyan

# 1. Load Config
if (-not (Test-Path $CONFIG_FILE)) { Write-Error "Config file not found: $CONFIG_FILE" }
$configContent = Get-Content -Path $CONFIG_FILE -Raw

# 2. Get Settings
$ag_user = Get-ConfigValue -Content $configContent -Section "adguard" -Key "username"
$ag_upstream = Get-ConfigList -Content $configContent -Section "adguard" -Key "upstream_dns"
$ag_blocklists = Get-ConfigList -Content $configContent -Section "adguard" -Key "blocklists"

# 3. Handle Passwords
$vpnPassword = Read-Host "Enter the password for WireGuard (VPN) UI"
if ([string]::IsNullOrWhiteSpace($vpnPassword)) { $vpnPassword = "password" }

$agPassword = Read-Host "Enter the password for AdGuard Home UI"
if ([string]::IsNullOrWhiteSpace($agPassword)) { $agPassword = "password" }

# 4. Prepare AdGuard Template
if (-not (Test-Path $TEMPLATE_ADGUARD)) { Write-Error "Template not found: $TEMPLATE_ADGUARD" }
$agTemplate = Get-Get-Content -Path $TEMPLATE_ADGUARD -Raw
$agTemplate = $agTemplate.Replace("{{ADGUARD_USER}}", $ag_user)
$agTemplate = $agTemplate.Replace("{{ADGUARD_PASS_HASH}}", "ADGUARD_HASH_PLACEHOLDER")

$dnsBlock = ""; foreach ($dns in $ag_upstream) { $dnsBlock += "    - $dns`n" }
$agTemplate = $agTemplate.Replace("{{UPSTREAM_DNS_BLOCK}}", $dnsBlock.TrimEnd())

$filterBlock = ""; $c = 1; foreach ($url in $ag_blocklists) { $filterBlock += "  - enabled: true`n    url: $url`n    name: List $c`n    id: $c`n"; $c++ }
$agTemplate = $agTemplate.Replace("{{BLOCKLISTS_BLOCK}}", $filterBlock.TrimEnd())

$indentedAg = ""; foreach ($line in ($agTemplate -split "`r?`n")) { $indentedAg += "      $line`n" }

# 5. Build Final Cloud-Init
$finalContent = @"
#cloud-config
package_update: true
package_upgrade: true
packages: [docker.io, docker-compose-v2, curl, ufw, apache2-utils]

write_files:
  - path: /root/adguard/conf/AdGuardHome.yaml
    permissions: '0644'
    content: |
$indentedAg

  - path: /root/Caddyfile
    content: |
      {
        email admin@sslip.io
      }
      adguard.DOMAIN_PLACEHOLDER {
        reverse_proxy adguardhome:8080 {
          header_up Host {upstream_hostport}
        }
      }
      vpn.DOMAIN_PLACEHOLDER {
        reverse_proxy wg-easy:51821
      }

  - path: /root/docker-compose.yml
    content: |
      services:
        caddy:
          image: caddy:latest
          container_name: caddy
          restart: unless-stopped
          ports: ["80:80", "443:443"]
          volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "./caddy_data:/data", "./caddy_config:/config"]
        wg-easy:
          image: ghcr.io/wg-easy/wg-easy
          container_name: wg-easy
          environment:
            - WG_HOST=auto
            - PASSWORD_HASH=VPN_HASH_PLACEHOLDER
            - WG_DEFAULT_DNS=172.20.0.53
            - WG_ALLOWED_IPS=0.0.0.0/0
          volumes: ["./wg-easy:/etc/wireguard"]
          ports: ["51820:51820/udp"]
          expose: ["51821"]
          restart: unless-stopped
          cap_add: [NET_ADMIN, SYS_MODULE]
          sysctls:
            - net.ipv4.ip_forward=1
            - net.ipv4.conf.all.src_valid_mark=1
        adguardhome:
          image: adguard/adguardhome
          container_name: adguardhome
          restart: unless-stopped
          volumes: ["./adguard/work:/opt/adguardhome/work", "./adguard/conf:/opt/adguardhome/conf"]
          ports: ["3000:3000/tcp"]
          expose: ["8080"]
          networks:
            default: { ipv4_address: 172.20.0.53 }
      networks:
        default:
          ipam:
            config: [{ subnet: 172.20.0.0/24 }]

  - path: /root/setup.sh
    permissions: '0700'
    content: |
      #!/bin/bash
      # Generate Bcrypt hashes using native tools
      VPN_PASS="$vpnPassword"
      AG_PASS="$agPassword"
      
      VPN_HASH=$(htpasswd -B -n -b admin "`$VPN_PASS" | cut -d ":" -f 2)
      AG_HASH=$(htpasswd -B -n -b admin "`$AG_PASS" | cut -d ":" -f 2)
      
      # Escape VPN hash for Docker Compose ($ -> $$)
      ESCAPED_VPN_HASH=$(echo "`$VPN_HASH" | sed 's/\$/\\$$/g')
      
      # Replace placeholders in configs
      sed -i "s|VPN_HASH_PLACEHOLDER|`$ESCAPED_VPN_HASH|g" /root/docker-compose.yml
      sed -i "s|ADGUARD_HASH_PLACEHOLDER|`$AG_HASH|g" /root/adguard/conf/AdGuardHome.yaml
      sed -i "s|session_ttl: 0s|session_ttl: 720h|g" /root/adguard/conf/AdGuardHome.yaml

      systemctl enable --now docker
      cd /root
      docker compose up -d
      ufw allow ssh; ufw allow 51820/udp; ufw allow 80/tcp; ufw allow 443/tcp
      echo "y" | ufw enable

runcmd:
  - bash /root/setup.sh
"@

[System.IO.File]::WriteAllText($OUTPUT_FILE, $finalContent, [System.Text.Encoding]::ASCII)
Write-Host "SUCCESS: '$OUTPUT_FILE' created with custom passwords." -ForegroundColor Green
