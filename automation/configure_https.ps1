# HTTPS Configuration Script - Robust Version
# Configures Caddy using IP-based Magic DNS (sslip.io).

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

# Smart Command: Wait for file availability then edit and restart
$cmd = @"
for i in {1..30}; do
    if [ -f /root/Caddyfile ]; then
        echo 'Found Caddyfile, applying domains...'
        sed -i "s/DOMAIN_PLACEHOLDER/$domainSuffix/g" /root/Caddyfile
        cd /root && docker compose restart caddy
        exit 0
    fi
    echo 'Waiting for Caddyfile to be created by system setup...'
    sleep 10
done
echo 'ERROR: Timeout waiting for Caddyfile.'
exit 1
"@

Show-Step "Syncing domains (adguard.$domainSuffix)..."
ssh -o StrictHostKeyChecking=no azureuser@$ServerIp "sudo bash -c '$cmd'"

if ($LASTEXITCODE -eq 0) {
    Show-Success "HTTPS Enabled successfully."
} else {
    Show-Error "HTTPS configuration failed."
}
