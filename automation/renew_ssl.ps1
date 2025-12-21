# SSL Certificate Renewal Maintenance Script (Force Renew)
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Settings
$config = Get-VpnConfig
$RG = $config.azure.resource_group
$VM = $config.azure.vm_name
$IP = $config.server.ip

if ([string]::IsNullOrWhiteSpace($IP)) { Show-Error "Server IP not found in config.yaml"; exit 1 }

Show-Header "SSL RENEWAL MAINTENANCE"

# 2. Get Admin IP
try {
    $AdminIp = Get-PublicIp
} catch {
    Show-Error "Could not detect Public IP."
    exit 1
}

# 3. Detect NSG
Show-Step "Detecting NSG..."
$NSG_NAME = Get-AzureNsgName -Rg $RG -Vm $VM

if (-not $NSG_NAME) { Show-Error "Could not find NSG."; exit 1 }

# 4. Open Firewall
Show-Step "Opening Ports 80/443..."
az network nsg rule update -g $RG --nsg-name $NSG_NAME --name AllowHTTP --source-address-prefixes "*" --output none
az network nsg rule update -g $RG --nsg-name $NSG_NAME --name AllowHTTPS --source-address-prefixes "*" --output none

# 5. Force Renew
Show-Step "Triggering renewal on server..."
ssh -o StrictHostKeyChecking=no azureuser@$IP "sudo docker compose -f /root/docker-compose.yml restart caddy"

Show-Step "Waiting 60s for validation..."
Start-Sleep -Seconds 60

# 6. Lockdown
Show-Step "Locking down ports to $AdminIp..."
az network nsg rule update -g $RG --nsg-name $NSG_NAME --name AllowHTTP --source-address-prefixes $AdminIp --output none
az network nsg rule update -g $RG --nsg-name $NSG_NAME --name AllowHTTPS --source-address-prefixes $AdminIp --output none

Show-Success "SSL Maintenance Complete."