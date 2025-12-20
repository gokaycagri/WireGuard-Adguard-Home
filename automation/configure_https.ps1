# HTTPS Configuration Script
# Configures Caddy using IP-based Magic DNS (sslip.io).

param (
    [string]$ServerIp
)

$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."

if (-not $ServerIp) {
    # Try reading from config file
    $configFile = "$ROOT_DIR\automation\config.yaml"
    if (Test-Path $configFile) {
         $content = Get-Content $configFile -Raw
         if ($content -match 'ip:\s*["'']?([0-9\.]+)["'']?') {
            $ServerIp = $Matches[1].Trim()
         }
    }
}

if (-not $ServerIp) {
    $ServerIp = Read-Host "Please enter the Server IP address"
}

Write-Host "--- Configuring HTTPS Settings ($ServerIp) ---" -ForegroundColor Cyan
Write-Host "Creating domains:"
Write-Host "AdGuard: adguard-$ServerIp.sslip.io"
Write-Host "VPN:     vpn-$ServerIp.sslip.io"

# Edit Caddyfile via SSH
$domainSuffix = "$ServerIp.sslip.io"
# Execute in /root with sudo
$cmd = "sudo bash -c 'sed -i ""s/DOMAIN_PLACEHOLDER/$domainSuffix/g"" /root/Caddyfile && cd /root && docker compose restart caddy'"

Write-Host "Connecting to server and applying settings..." -ForegroundColor Yellow
ssh -o StrictHostKeyChecking=no azureuser@$ServerIp $cmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "HTTPS Successfully Enabled! [OK]" -ForegroundColor Green
    Write-Host "Addresses:"
    Write-Host "AdGuard: https://adguard.$ServerIp.sslip.io"
    Write-Host "VPN:     https://vpn.$ServerIp.sslip.io"
} else {
    Write-Host "ERROR: Could not apply HTTPS settings." -ForegroundColor Red
}