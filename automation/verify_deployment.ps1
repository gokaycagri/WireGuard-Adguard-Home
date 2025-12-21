# Server Health & Security Verification
param ([string]$ServerIp)
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

if (!$ServerIp) { $config = Get-VpnConfig; $ServerIp = $config.server.ip }
if (!$ServerIp) { Show-Error "No Server IP provided."; exit 1 }

Show-Header "VERIFYING DEPLOYMENT HEALTH"
Show-Step "Target: $ServerIp"

# Using simpler grep patterns to avoid escaping issues
$checkCmd = "echo '--- Docker ---'; sudo docker ps --format 'table {{.Names}}\t{{.Status}}'; " +
            "echo '--- Files ---'; [ -f /root/docker-compose.yml ] && echo '[OK] Compose exists'; " +
            "echo '--- VPN Hash ---'; sudo grep 'PASSWORD_HASH' /root/docker-compose.yml | head -n 1"

ssh -o StrictHostKeyChecking=no azureuser@$ServerIp "$checkCmd"

Show-Success "System is up! Please try accessing your dashboard."
