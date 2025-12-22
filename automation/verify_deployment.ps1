# Server Health & Security Verification
param ([string]$ServerIp)
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

if (!$ServerIp) { $config = Get-VpnConfig; $ServerIp = $config.server.ip }
if (!$ServerIp) { Show-Error "No Server IP provided."; exit 1 }

Show-Header "VERIFYING DEPLOYMENT HEALTH"
Show-Step "Target: $ServerIp"

# Robust health check command (Using sudo for file checks)
$checkCmd = @"
echo '--- Docker Containers ---'
sudo docker ps --format 'table {{.Names}}  {{.Status}}  {{.Ports}}' || echo 'Docker failed'
echo '--- Listening Ports ---'
sudo ss -tulpn | grep -E ':80|:443|:51820|:8080|:3000|:53' || echo 'Ports check failed'
echo '--- Critical Files ---'
sudo [ -f /root/docker-compose.yml ] && echo '[OK] Compose file found' || echo '[FAIL] Compose file missing'
sudo [ -f /root/adguard/conf/AdGuardHome.yaml ] && echo '[OK] AdGuard config found' || echo '[FAIL] AdGuard config missing'
"@

ssh -o StrictHostKeyChecking=no azureuser@$ServerIp "$checkCmd"

if ($LASTEXITCODE -eq 0) {
    Show-Success "Health check finished."
} else {
    Show-Error "Health check returned errors."
}
