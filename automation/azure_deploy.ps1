# Azure Deployment Script - Clean Code Edition
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\lib.ps1"

# 1. Load Configuration
$Config = Get-VpnConfig
if (-not $Config) { Show-Error "Config not found!"; exit 1 }

$ResourceGroup = $Config.azure.resource_group
$Location      = $Config.azure.location
$VmName        = $Config.azure.vm_name
$AdminUser     = $Config.azure.admin_user
$CloudInitFile = Join-Path $ScriptDir "..\final_cloud_init.yaml"

if ([string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($VmName)) {
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

# 3. Create Resource Group
Show-Step "Creating Resource Group ($ResourceGroup)..."
az group create --name $ResourceGroup --location $Location --output none

# 4. Provision VM
Show-Step "Provisioning VM ($VmName)..."
$VNetArgs = @()
if (-not [string]::IsNullOrWhiteSpace($Config.azure.vnet_name)) {
    Show-Step "Using existing VNet: $($Config.azure.vnet_name)"
    $VNetArgs += "--vnet-name", $Config.azure.vnet_name
    if (-not [string]::IsNullOrWhiteSpace($Config.azure.subnet_name)) {
        $VNetArgs += "--subnet", $Config.azure.subnet_name
    }
}

az vm create `
  --resource-group $ResourceGroup `
  --name $VmName `
  --image "Canonical:ubuntu-24_04-lts:server:latest" `
  --size $Config.azure.vm_size `
  --admin-username $AdminUser `
  --generate-ssh-keys `
  --public-ip-sku Standard `
  --public-ip-address-allocation static `
  --custom-data $CloudInitFile `
  @VNetArgs `
  --output none

# 5. Network Security Hardening
Show-Step "Hardening Network (NSG)..."
$NsgName = "${VmName}NSG"

# Attempt to remove default SSH rule
az network nsg rule delete -g $ResourceGroup --nsg-name $NsgName --name default-allow-ssh --output none 2>$null

# Public VPN Port (UDP 51820) - Always Open
az network nsg rule create -g $ResourceGroup --nsg-name $NsgName --name AllowVPN --priority 1010 --protocol Udp --destination-port-ranges 51820 --access Allow --source-address-prefixes "*" --output none

# Management Ports (Restricted to Admin IP)
az network nsg rule create -g $ResourceGroup --nsg-name $NsgName --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --source-address-prefixes $AdminIp --output none
az network nsg rule create -g $ResourceGroup --nsg-name $NsgName --name AllowHTTP --priority 1020 --protocol Tcp --destination-port-ranges 80 --access Allow --source-address-prefixes "*" --output none
az network nsg rule create -g $ResourceGroup --nsg-name $NsgName --name AllowHTTPS --priority 1030 --protocol Tcp --destination-port-ranges 443 --access Allow --source-address-prefixes $AdminIp --output none

# 6. Finalize Config
$PublicIp = az vm show -g $ResourceGroup -n $VmName --show-details --query publicIps --output tsv
$ConfigContent = Get-Content "$ScriptDir\config.yaml" -Raw
$NewContent = $ConfigContent -replace '(?m)^(\s+ip:\s*).*$', "`$1`"$PublicIp`""
Set-Content -Path "$ScriptDir\config.yaml" -Value $NewContent

Show-Success "Deployment stage 1 finished. Server IP: $PublicIp"
