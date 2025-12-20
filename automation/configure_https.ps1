# HTTPS Configuration Script - Robust Quoting
param (
    [string]$ServerIp
)

$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

if (!$ServerIp) {
    $config = Get-VpnConfig
    $ServerIp = $config.server.ip
}

if (!$ServerIp) { $ServerIp = Read-Host "  Please enter the Server IP address" }

Show-Header "CONFIGURING HTTPS"
Show-Step "Target: $ServerIp"

$domainSuffix = "$ServerIp.sslip.io"

# Wait for Caddyfile and then apply domain
Show-Step "Applying domains (adguard.$domainSuffix)..."

# Simplified command: retry logic moved to a single-line bash string
$cmd = "for i in {1..30}; do if [ -f /root/Caddyfile ]; then sed -i 's/DOMAIN_PLACEHOLDER/$domainSuffix/g' /root/Caddyfile && cd /root && docker compose restart caddy && exit 0; fi; echo 'Waiting...'; sleep 10; done; exit 1"

ssh -o StrictHostKeyChecking=no azureuser@$ServerIp "sudo bash -c `"$cmd`""

if ($LASTEXITCODE -eq 0) {
    Show-Success "HTTPS Enabled successfully."
} else {
    Show-Error "HTTPS configuration failed."
}