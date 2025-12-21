# SSL Certificate Renewal Script - Clean Code Edition
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\lib.ps1"

# 1. Load Configuration
$Config = Get-VpnConfig
$ResourceGroup = $Config.azure.resource_group
$VmName        = $Config.azure.vm_name
$ServerIp      = $Config.server.ip

if ([string]::IsNullOrWhiteSpace($ServerIp)) { Show-Error "Server IP not found in config.yaml"; exit 1 }

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
$NsgName = Get-AzureNsgName -ResourceGroup $ResourceGroup -VmName $VmName

if (-not $NsgName) { Show-Error "Could not find NSG."; exit 1 }

# 4. Open Firewall for Let's Encrypt
Show-Step "Opening Ports 80/443..."
az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTP --source-address-prefixes "*" --output none
az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTPS --source-address-prefixes "*" --output none

# 5. Force Renewal
Show-Step "Triggering renewal on server..."
ssh -o StrictHostKeyChecking=no azureuser@$ServerIp "sudo docker compose -f /root/docker-compose.yml restart caddy"

Show-Step "Waiting 60s for validation..."
Start-Sleep -Seconds 60

# 6. Lockdown Firewall
Show-Step "Locking down ports to $AdminIp..."
az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTP --source-address-prefixes $AdminIp --output none
az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTPS --source-address-prefixes $AdminIp --output none

Show-Success "SSL Maintenance Complete."
