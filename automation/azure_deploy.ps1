# Azure Deployment Script - Enterprise Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
if (!$config) { Show-Error "Config not found!"; exit 1 }

$RG      = $config.azure.resource_group
$Loc     = $config.azure.location
$VM      = $config.azure.vm_name
$User    = $config.azure.admin_user
$Cloud   = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"

if ([string]::IsNullOrWhiteSpace($RG) -or [string]::IsNullOrWhiteSpace($VM)) {
    Show-Error "Critical variables missing in config.yaml! Please run setup.ps1 again."
    exit 1
}

# 2. Get Admin IP
Show-Step "Detecting your Public IP..."
try {
    $AdminIp = Get-PublicIp
    Show-Success "Detected IP: $AdminIp"
} catch {
    Show-Error "Could not detect Public IP. Defaulting to open access (*)."
    $AdminIp = "*"
}

# 3. Resource Group
Show-Step "Creating Resource Group ($RG)..."
az group create --name $RG --location $Loc --output none

# 4. Create VM
Show-Step "Provisioning VM ($VM)..."
$vnetArgs = @()
if (-not [string]::IsNullOrWhiteSpace($config.azure.vnet_name)) {
    Show-Step "Using existing VNet: $($config.azure.vnet_name)"
    $vnetArgs += "--vnet-name", $config.azure.vnet_name
    if (-not [string]::IsNullOrWhiteSpace($config.azure.subnet_name)) {
        $vnetArgs += "--subnet", $config.azure.subnet_name
    }
}

az vm create `
  --resource-group $RG `
  --name $VM `
  --image "Canonical:ubuntu-24_04-lts:server:latest" `
  --size $config.azure.vm_size `
  --admin-username $User `
  --generate-ssh-keys `
  --public-ip-sku Standard `
  --public-ip-address-allocation static `
  --custom-data $Cloud `
  @vnetArgs `
  --output none

# 5. Network Security
Show-Step "Hardening Network (NSG)..."
$NSG = "${VM}NSG"
# Try to delete default rule safely
az network nsg rule delete -g $RG --nsg-name $NSG --name default-allow-ssh --output none 2>$null

# Public VPN Port
az network nsg rule create -g $RG --nsg-name $NSG --name AllowVPN --priority 1010 --protocol Udp --destination-port-ranges 51820 --access Allow --source-address-prefixes "*" --output none

# Admin-Only Ports
az network nsg rule create -g $RG --nsg-name $NSG --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --source-address-prefixes $AdminIp --output none
az network nsg rule create -g $RG --nsg-name $NSG --name AllowHTTP --priority 1020 --protocol Tcp --destination-port-ranges 80 --access Allow --source-address-prefixes "*" --output none
az network nsg rule create -g $RG --nsg-name $NSG --name AllowHTTPS --priority 1030 --protocol Tcp --destination-port-ranges 443 --access Allow --source-address-prefixes $AdminIp --output none

# 6. Finalize
$Ip = az vm show -g $RG -n $VM --show-details --query publicIps --output tsv
$content = Get-Content "$SCRIPT_DIR\config.yaml" -Raw
$newContent = $content -replace '(?m)^(\s+ip:\s*).*$', "`$1`"$Ip`""
Set-Content -Path "$SCRIPT_DIR\config.yaml" -Value $newContent

Show-Success "Deployment stage 1 finished. Server IP: $Ip"