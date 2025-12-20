# Azure Automatic Deployment Script (PowerShell)

# Error handling
$ErrorActionPreference = "Stop"

# --- SETTINGS ---
$RESOURCE_GROUP = "MyVPN_Group"
$LOCATION = "northeurope"
$VM_NAME = "MyVPN-VM"
$VM_IMAGE = "Ubuntu2404"
$VM_SIZE = "Standard_B1s"
$ADMIN_USER = "azureuser"
$CLOUD_INIT_FILE = "final_cloud_init.yaml"

# File check
if (-not (Test-Path $CLOUD_INIT_FILE)) {
    Write-Host "ERROR: $CLOUD_INIT_FILE not found! Please run 'powershell automation/generate_cloud_init.ps1' first." -ForegroundColor Red
    exit 1
}

# Admin IP Detection
Write-Host "[0/6] Detecting Public IP address..." -ForegroundColor Cyan
try {
    $ADMIN_IP = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    Write-Host "   Admin IP: $ADMIN_IP (Security rules will be locked to this IP)" -ForegroundColor Green
} catch {
    Write-Host "   IP could not be detected, security rules will be open to everyone (*)." -ForegroundColor Yellow
    $ADMIN_IP = "*"
}

# Azure Login Check
Write-Host "[1/6] Checking Azure login..." -ForegroundColor Cyan
try {
    az account show | Out-Null
} catch {
    Write-Host "Please login first:" -ForegroundColor Yellow
    az login
}

Write-Host "[2/6] Creating Resource Group ($RESOURCE_GROUP)..." -ForegroundColor Cyan
az group create --name $RESOURCE_GROUP --location $LOCATION --output none

Write-Host "[3/6] Creating VM (with Static IP)..." -ForegroundColor Cyan
$cloudInitPath = Resolve-Path $CLOUD_INIT_FILE
az vm create `
  --resource-group $RESOURCE_GROUP `
  --name $VM_NAME `
  --image $VM_IMAGE `
  --size $VM_SIZE `
  --admin-username $ADMIN_USER `
  --generate-ssh-keys `
  --public-ip-sku Standard `
  --public-ip-address-allocation static `
  --custom-data $cloudInitPath `
  --output none

Write-Host "[4/6] Configuring Ports and Firewall..." -ForegroundColor Cyan

# 1. WireGuard UDP (51820) - VPN Connection
# Must be GLOBAL (*) to allow connecting from phone/work etc.
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name "${VM_NAME}NSG" --name AllowWireGuardUDP --priority 1010 --protocol Udp --destination-port-ranges 51820 --access Allow --direction Inbound --source-address-prefixes "*" --output none

# 2. SSH (22) - Admin IP Only
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name "${VM_NAME}NSG" --name AllowSSH --priority 1000 --protocol Tcp --destination-port-ranges 22 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none

# 3. HTTP (80) - Admin IP Only
# Note: If restricted to your IP only, Caddy/Let's Encrypt might fail auto-renewal (after 90 days).
# You might need to open this port temporarily when renewal is due. Locked for security for now.
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name "${VM_NAME}NSG" --name AllowHTTP --priority 1020 --protocol Tcp --destination-port-ranges 80 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none

# 4. HTTPS (443) - Web UI - Admin IP Only
az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name "${VM_NAME}NSG" --name AllowHTTPS --priority 1030 --protocol Tcp --destination-port-ranges 443 --access Allow --direction Inbound --source-address-prefixes $ADMIN_IP --output none

Write-Host "[5/6] Retrieving IP Address..." -ForegroundColor Cyan
$IP_ADDRESS = az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --show-details --query publicIps --output tsv

Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Server IP Address (Static): $IP_ADDRESS" -ForegroundColor Green
Write-Host "Management Access Locked to IP: $ADMIN_IP" -ForegroundColor Yellow
Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Please save this IP address to 'automation/config.yaml'."
Write-Host "Then run 'powershell automation/verify_deployment.ps1'."
Write-Host "Note: If your IP address changes (modem reset etc.), you must update NSG rules in Azure Portal." -ForegroundColor Gray
