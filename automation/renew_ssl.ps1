# SSL Certificate Renewal Maintenance Script (Force Renew)
$ErrorActionPreference = "Stop"

$SCRIPT_DIR = $PSScriptRoot
$CONFIG_FILE = "$SCRIPT_DIR\config.yaml"

function Get-ConfigValue {
    param ([string]$Section, [string]$Key)
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") { $inSection = $true; continue }
        if ($inSection -and $line -match "^\w+\s*:") { $inSection = $false }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*[`"']?([^`"']+)`?['`"]?") { return $Matches[1].Trim() }
    }
    return $null
}

# 1. Load Settings
$RG       = Get-ConfigValue -Section "azure" -Key "resource_group"
$VM_NAME  = Get-ConfigValue -Section "azure" -Key "vm_name"
$NSG_NAME = "${VM_NAME}NSG"
$IP       = Get-ConfigValue -Section "server" -Key "ip"
$ADMIN_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()

if ([string]::IsNullOrWhiteSpace($IP)) { Write-Error "Server IP not found in config.yaml" }

Write-Host "--- Starting Forced SSL Renewal Maintenance ---" -ForegroundColor Cyan

# 2. Open Firewall
Write-Host "[*] Opening Port 80/443 to the world temporarily..." -ForegroundColor Yellow
az network nsg rule update --resource-group $RG --nsg-name $NSG_NAME --name AllowHTTP --source-address-prefixes "*" --output none
az network nsg rule update --resource-group $RG --nsg-name $NSG_NAME --name AllowHTTPS --source-address-prefixes "*" --output none

# 3. Force Caddy to check for certificates
Write-Host "[*] Triggering Caddy certificate renewal check..." -ForegroundColor Yellow
# Restarting Caddy forces a re-evaluation of all managed certificates
ssh -o StrictHostKeyChecking=no azureuser@$IP "sudo docker compose -f /root/docker-compose.yml restart caddy"

# 4. Wait for Let's Encrypt
Write-Host "[*] Waiting 60 seconds for validation and download..." -ForegroundColor Gray
Start-Sleep -Seconds 60

# 5. Lockdown
Write-Host "[*] Renewal window finished. Restricting access to $ADMIN_IP again..." -ForegroundColor Yellow
az network nsg rule update --resource-group $RG --nsg-name $NSG_NAME --name AllowHTTP --source-address-prefixes $ADMIN_IP --output none
az network nsg rule update --resource-group $RG --nsg-name $NSG_NAME --name AllowHTTPS --source-address-prefixes $ADMIN_IP --output none

Write-Host "--- SSL Maintenance Complete. System is Secure again. ---" -ForegroundColor Green