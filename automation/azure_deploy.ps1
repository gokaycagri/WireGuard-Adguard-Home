# Azure Automatic Deployment Script (PowerShell)
$ErrorActionPreference = "Stop"

# --- Shared Utilities ---
$SCRIPT_DIR = $PSScriptRoot
$CONFIG_FILE = "$SCRIPT_DIR\config.yaml"
$CLOUD_INIT_FILE = "$SCRIPT_DIR\..\final_cloud_init.yaml"

# Simplified Config Reader (Cleaner and more robust)
function Get-ConfigValue {
    param ([string]$Section, [string]$Key)
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match "^\w+\s*:") {
            $inSection = $false
        }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*[`"']?([^`"']+)`?['`"]?") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

# 1. Load Configuration
if (-not (Test-Path $CONFIG_FILE)) { Write-Error "Config file not found at $CONFIG_FILE" }

$RESOURCE_GROUP = Get-ConfigValue -Section "azure" -Key "resource_group"
$LOCATION       = Get-ConfigValue -Section "azure" -Key "location"
$VM_NAME        = Get-ConfigValue -Section "azure" -Key "vm_name"
$VM_SIZE        = Get-ConfigValue -Section "azure" -Key "vm_size"
$ADMIN_USER     = Get-ConfigValue -Section "azure" -Key "admin_user"

if (-not $RESOURCE_GROUP) { Write-Error "Could not read Resource Group from config!" }

# 2. Detecting Public IP
Write-Host "[*] Detecting Public IP address..." -ForegroundColor Cyan
try {
    $ADMIN_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    Write-Host "   Admin IP: $ADMIN_IP" -ForegroundColor Green
} catch {
    Write-Host "   Could not detect IP, setting to wildcard (*)." -ForegroundColor Yellow
    $ADMIN_IP = "*"
}

# 3. Azure Login Check
Write-Host "[*] Checking Azure login..." -ForegroundColor Cyan
try { az account show | Out-Null } catch { az login }

# 4. Infrastructure Creation
Write-Host "[*] Creating Resource Group ($RESOURCE_GROUP)..." -ForegroundColor Cyan
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

Write-Host "[*] Creating VM ($VM_NAME)..." -ForegroundColor Cyan
$cloudInitPath = Resolve-Path $CLOUD_INIT_FILE
az vm create `
  --resource-group $RESOURCE_GROUP `
  --name $VM_NAME `
  --image Ubuntu2404 `
  --size $VM_SIZE `
  --admin-username $ADMIN_USER `
  --generate-ssh-keys `
  --public-ip-sku Standard `
  --public-ip-address-allocation static `
  --custom-data $cloudInitPath `
  --output none

# 5. NSG Configuration
Write-Host "[*] Configuring NSG Rules..." -ForegroundColor Cyan
$NSG_NAME = "${VM_NAME}NSG"

# Delete default SSH rule if it exists to avoid conflicts
az network nsg rule delete --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name default-allow-ssh --output none 2>$null

# Allowed Everywhere
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name AllowWireGuardUDP --priority 1010 --protocol Udp --destination-port-ranges 51820 --access Allow --direction Inbound --source-address-prefixes "*" --output none

# Restricted to Admin IP
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name AllowHTTP --priority 1020 --protocol Tcp --destination-port-ranges 80 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name AllowHTTPS --priority 1030 --protocol Tcp --destination-port-ranges 443 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none

# 6. Retrieving IP Address
$IP_ADDRESS = az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --query publicIps --output tsv

# Update config.yaml with the real IP
$configContent = Get-Content -Path $CONFIG_FILE -Raw
$newConfig = $configContent -replace 'ip:\s*["'']?[0-9\.]*["'']?', "ip: `"$IP_ADDRESS`""
Set-Content -Path $CONFIG_FILE -Value $newConfig

Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Deployment Successful!" -ForegroundColor Green
Write-Host "Server IP: $IP_ADDRESS" -ForegroundColor Green
Write-Host "Access restricted to: $ADMIN_IP" -ForegroundColor Yellow
Write-Host "--------------------------------------------------" -ForegroundColor Green