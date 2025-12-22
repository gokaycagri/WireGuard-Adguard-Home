# HTTPS Configuration Script - Intelligent Wait
param ([string]$ServerIp)
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\lib.ps1"

if (!$ServerIp) { $config = Get-VpnConfig; $ServerIp = $config.server.ip }
if (!$ServerIp) { Show-Error "No Server IP provided."; exit 1 }

Show-Header "CONFIGURING HTTPS"
Show-Step "Target: $ServerIp"

$domainSuffix = "$ServerIp.sslip.io"

# Create an intelligent helper script
$remoteScript = @"
#!/bin/bash
echo "Starting intelligent HTTPS configuration..."

# 1. Wait for Docker
for i in {1..60}; do
    if command -v docker >/dev/null 2>&1; then
        echo "[OK] Docker is installed."
        break
    fi
    echo "Waiting for Docker installation... (\$i/60)"
    sleep 10
done

# 2. Wait for Caddyfile and Compose file
for i in {1..30}; do
    if [ -f /root/Caddyfile ] && [ -f /root/docker-compose.yml ]; then
        echo "[OK] Configuration files found."
        
        # Apply domains
        sed -i "s/DOMAIN_PLACEHOLDER/$domainSuffix/g" /root/Caddyfile
        
        # 3. Wait for Containers to be ready to restart
        echo "Restarting Caddy to apply SSL..."
        cd /root && sudo docker compose restart caddy
        exit 0
    fi
    echo "Waiting for configuration files... (\$i/30)"
    sleep 10
done

echo "ERROR: Timeout waiting for system readiness."
exit 1
"@

$tempFile = Join-Path $env:TEMP "configure_https.sh"
Set-Content -Path $tempFile -Value $remoteScript -Encoding UTF8

Show-Step "Syncing domains (adguard.$domainSuffix)..."
try {
    scp -o StrictHostKeyChecking=no $tempFile azureuser@${ServerIp}:/tmp/configure_https.sh
    ssh -o StrictHostKeyChecking=no azureuser@${ServerIp} "chmod +x /tmp/configure_https.sh; sudo /tmp/configure_https.sh"
    
    if ($LASTEXITCODE -eq 0) {
        Show-Success "HTTPS Enabled successfully."
    } else {
        Show-Error "HTTPS configuration failed."
    }
} catch {
    Show-Error "Connection failed: $_"
}
Remove-Item $tempFile -ErrorAction SilentlyContinue