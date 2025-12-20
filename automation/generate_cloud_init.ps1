# PowerShell Cloud-Init Generator
# Exact port of Python script.

$ErrorActionPreference = "Stop"

# --- File Paths ---
$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."
$CONFIG_FILE = "$ROOT_DIR\automation\config.yaml"
$TEMPLATE_ADGUARD = "$ROOT_DIR\automation\templates\AdGuardHome.yaml"
$OUTPUT_FILE = "$ROOT_DIR\final_cloud_init.yaml"

# --- Functions ---

function Get-ConfigValue {
    param (
        [string]$Content,
        [string]$Section,
        [string]$Key
    )
    # 1. Find Section
    $sectionPattern = '(?ms)^' + [regex]::Escape($Section) + ':\s*$(.+?)(?=^\w+:|\Z)'
    $sectionMatch = [regex]::Match($Content, $sectionPattern)
    
    if ($sectionMatch.Success) {
        $sectionContent = $sectionMatch.Groups[1].Value
        # 2. Find Key (Simple regex: Key: Value)
        # Capture full value, trim later.
        $keyPattern = '^\s+' + [regex]::Escape($Key) + ':\s*(.+)$'
        $keyMatch = [regex]::Match($sectionContent, $keyPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($keyMatch.Success) {
            $value = $keyMatch.Groups[1].Value.Trim()
            # Remove quotes
            return $value.Trim('"').Trim("'")
        }
    }
    return $null
}

function Get-ConfigList {
    param (
        [string]$Content,
        [string]$Section,
        [string]$Key
    )
    $list = @()
    $sectionPattern = '(?ms)^' + [regex]::Escape($Section) + ':\s*$(.+?)(?=^\w+:|\Z)'
    $sectionMatch = [regex]::Match($Content, $sectionPattern)
    
    if ($sectionMatch.Success) {
        $sectionContent = $sectionMatch.Groups[1].Value
        # Find list block
        $listPattern = '(?ms)^\s+' + [regex]::Escape($Key) + ':\s*$(\s+-\s+[^\r\n]+[\r\n]*)+' 
        $listBlockMatch = [regex]::Match($sectionContent, $listPattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($listBlockMatch.Success) {
            $rawList = $listBlockMatch.Value
            # Read line by line and parse
            $lines = $rawList -split "`r?`n"
            foreach ($line in $lines) {
                if ($line -match '^\s+-\s+(.+)$') {
                    $val = $Matches[1].Trim()
                    $list += $val.Trim('"').Trim("'")
                }
            }
        }
    }
    return $list
}

Write-Host "Generating automation files (PowerShell Edition)..." -ForegroundColor Cyan

# 1. Read Config File
if (-not (Test-Path $CONFIG_FILE)) {
    Write-Error "Config file not found: $CONFIG_FILE"
}
$configContent = Get-Content -Path $CONFIG_FILE -Raw

# 2. Parse Values
$wg_hash = Get-ConfigValue -Content $configContent -Section "wireguard" -Key "password_hash"
$ag_user = Get-ConfigValue -Content $configContent -Section "adguard" -Key "username"
$ag_pass = Get-ConfigValue -Content $configContent -Section "adguard" -Key "password_hash"
$ag_upstream = Get-ConfigList -Content $configContent -Section "adguard" -Key "upstream_dns"
$ag_blocklists = Get-ConfigList -Content $configContent -Section "adguard" -Key "blocklists"

# Docker Compose escaping for WireGuard ($ -> $$)
$wg_hash_escaped = $wg_hash.Replace('$', '$$')

if ([string]::IsNullOrWhiteSpace($wg_hash)) { Write-Warning "WireGuard hash not found!" }
if ([string]::IsNullOrWhiteSpace($ag_user)) { Write-Warning "AdGuard user not found!" }

Write-Host "Loaded config for user: $ag_user" -ForegroundColor Gray

# 3. AdGuard Template Processing
if (-not (Test-Path $TEMPLATE_ADGUARD)) {
    Write-Error "Template file not found: $TEMPLATE_ADGUARD"
}
$templateContent = Get-Content -Path $TEMPLATE_ADGUARD -Raw

# String replacement
$templateContent = $templateContent.Replace("{{ADGUARD_USER}}", $ag_user)
$templateContent = $templateContent.Replace("{{ADGUARD_PASS_HASH}}", $ag_pass)

# Upstream DNS
$upstreamBlock = ""
foreach ($dns in $ag_upstream) {
    $upstreamBlock += "    - $dns`n"
}
$templateContent = $templateContent.Replace("{{UPSTREAM_DNS_BLOCK}}", $upstreamBlock.TrimEnd())

# Blocklists
$blocklistBlock = ""
$counter = 1
foreach ($url in $ag_blocklists) {
    $blocklistBlock += "  - enabled: true`n    url: $url`n    name: Filter List $counter`n    id: $counter`n"
    $counter++
}
$templateContent = $templateContent.Replace("{{BLOCKLISTS_BLOCK}}", $blocklistBlock.TrimEnd())

# 4. Generate Cloud-Init File
$adguardContentIndented = ""
foreach ($line in ($templateContent -split "`r?`n")) {
    $adguardContentIndented += "      $line`n"
}

$finalContent = @"
#cloud-config
package_update: true
package_upgrade: true

packages:
  - docker.io
  - docker-compose-v2
  - curl
  - ufw

write_files:
  - path: /root/adguard/conf/AdGuardHome.yaml
    permissions: '0644'
    content: |
$adguardContentIndented

  - path: /root/Caddyfile
    content: |
      {
        email admin@example.com
      }

      # AdGuard Home
      adguard.DOMAIN_PLACEHOLDER {
        reverse_proxy adguardhome:8080 {
          header_up Host {upstream_hostport}
        }
      }

      # WireGuard UI
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
          ports:
            - "80:80"
            - "443:443"
          volumes:
            - ./Caddyfile:/etc/caddy/Caddyfile
            - ./caddy_data:/data
            - ./caddy_config:/config
          networks:
            - default

        wg-easy:
          environment:
            - WG_HOST=auto
            - PASSWORD_HASH=$wg_hash_escaped
            - WG_PORT=51820
            - WG_DEFAULT_DNS=172.20.0.53
            - WG_ALLOWED_IPS=0.0.0.0/0
          image: ghcr.io/wg-easy/wg-easy
          container_name: wg-easy
          volumes:
            - ./wg-easy:/etc/wireguard
          ports:
            - "51820:51820/udp"
            # Web UI port closed externally, managed by Caddy
            # - "51821:51821/tcp"
          expose:
            - "51821"
          restart: unless-stopped
          cap_add:
            - NET_ADMIN
            - SYS_MODULE
          sysctls:
            - net.ipv4.ip_forward=1
            - net.ipv4.conf.all.src_valid_mark=1

        adguardhome:
          image: adguard/adguardhome
          container_name: adguardhome
          restart: unless-stopped
          volumes:
            - ./adguard/work:/opt/adguardhome/work
            - ./adguard/conf:/opt/adguardhome/conf
          ports:
            - "3000:3000/tcp"
            # Admin panel closed externally, managed by Caddy
            # - "8080:8080/tcp"
          expose:
            - "8080"
          networks:
            default:
              ipv4_address: 172.20.0.53

      networks:
        default:
          ipam:
            driver: default
            config:
              - subnet: 172.20.0.0/24

  - path: /root/setup.sh
    permissions: '0700'
    content: |
      #!/bin/bash
      systemctl enable --now docker
      cd /root
      docker compose up -d
      ufw default deny incoming
      ufw default allow outgoing
      ufw allow ssh
      ufw allow 51820/udp
      ufw allow 51821/tcp
      ufw allow 8080/tcp
      echo "y" | ufw enable

runcmd:
  - bash /root/setup.sh
"@

# Write to file
[System.IO.File]::WriteAllText($OUTPUT_FILE, $finalContent, [System.Text.Encoding]::ASCII)

Write-Host "SUCCESS: '$OUTPUT_FILE' created." -ForegroundColor Green
