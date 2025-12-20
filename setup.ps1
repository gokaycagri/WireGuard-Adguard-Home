# Professional VPN Setup CLI
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$CONFIG_FILE = "$SCRIPT_DIR\automation\config.yaml"

Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   AZURE WIREGUARD & ADGUARD HOME SETUP CLI" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# 1. Check Requirements
Write-Host "[*] Checking system requirements..." -ForegroundColor Gray
& "$SCRIPT_DIR\automation\check_requirements.ps1"
Write-Host ""

# 2. Collect Information
Write-Host "--- Infrastructure Settings ---" -ForegroundColor Yellow

# Resource Group
$currentRG = "MyVPN_Group"
$rg = Read-Host "Enter Azure Resource Group Name (default: $currentRG)"
if ([string]::IsNullOrWhiteSpace($rg)) { $rg = $currentRG }

# VM Name
$currentVMName = "MyVPN-VM"
$vmName = Read-Host "Enter VM Name (default: $currentVMName)"
if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = $currentVMName }

# Azure Region
$currentRegion = "northeurope"
$region = Read-Host "Enter Azure Region (default: $currentRegion)"
if ([string]::IsNullOrWhiteSpace($region)) { $region = $currentRegion }

# VM Size
$currentSize = "Standard_B1s"
$size = Read-Host "Enter VM Size (default: $currentSize)"
if ([string]::IsNullOrWhiteSpace($size)) { $size = $currentSize }

# Admin User
$currentAdmin = "azureuser"
$adminUser = Read-Host "Enter Admin Username (default: $currentAdmin)"
if ([string]::IsNullOrWhiteSpace($adminUser)) { $adminUser = $currentAdmin }

# Allowed Country
$currentCountry = "TR"
$country = Read-Host "Enter Allowed Country Code for Firewall (e.g. TR, US, DE) (default: $currentCountry)"
if ([string]::IsNullOrWhiteSpace($country)) { $country = $currentCountry }

# Passwords
Write-Host ""
Write-Host "--- Dashboard Passwords ---" -ForegroundColor Yellow
$vpnPass = Read-Host "Set WireGuard VPN Password"
if ([string]::IsNullOrWhiteSpace($vpnPass)) { $vpnPass = "password" }

$agPass = Read-Host "Set AdGuard Home Password"
if ([string]::IsNullOrWhiteSpace($agPass)) { $agPass = "password" }

# 3. Update config.yaml
Write-Host ""
Write-Host "[*] Updating configuration file..." -ForegroundColor Cyan

$configTemplate = @"
# VPN & AdGuard Automation Settings

# Azure Infrastructure Settings
azure:
  resource_group: "$rg"
  location: "$region"
  vm_name: "$vmName"
  vm_size: "$size"
  admin_user: "$adminUser"
  allowed_country: "$country"

# Server Connection Info
server:
  ip: "0.0.0.0"
  ssh_key_path: "~/.ssh/id_rsa"

# AdGuard Home Settings
adguard:
  username: "admin"
  upstream_dns:
    - "https://dns.cloudflare.com/dns-query"
    - "tls://1.1.1.1"
  blocklists:
    - "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"
"@

Set-Content -Path $CONFIG_FILE -Value $configTemplate

# 4. Generate Cloud-Init
Write-Host "[*] Generating deployment files..." -ForegroundColor Cyan
$inputPass = "$vpnPass`n$agPass"
$inputPass | & "$SCRIPT_DIR\automation\generate_cloud_init.ps1" | Out-Null

Write-Host ""
Write-Host "===============================================" -ForegroundColor Green
Write-Host "   CONFIGURATION READY!" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resource Group: $rg"
Write-Host "VM Name:        $vmName"
Write-Host "Region:         $region"
Write-Host "VM Size:        $size"
Write-Host "Admin User:     $adminUser"
Write-Host "Country:        $country"
Write-Host ""

$choice = Read-Host "Do you want to start Azure Deployment now? (y/n)"
if ($choice -eq "y") {
    Write-Host "[!] Starting Deployment... This will take a few minutes." -ForegroundColor Yellow
    & "$SCRIPT_DIR\automation\azure_deploy.ps1"
    
    # Retrieving IP after deployment
    $configContent = Get-Content $CONFIG_FILE -Raw
    if ($configContent -match 'ip:\s*["'']?([0-9\.]+)["'']?') {
        $ServerIp = $Matches[1].Trim()
    }

    Write-Host ""
    Write-Host "[!] Finalizing HTTPS Setup..." -ForegroundColor Yellow
    Write-Host "Waiting 60 seconds for server initialization..."
    Start-Sleep -Seconds 60
    & "$SCRIPT_DIR\automation\configure_https.ps1" -ServerIp $ServerIp
    
    Write-Host ""
    Write-Host "Deployment finished successfully!" -ForegroundColor Green
} else {
    Write-Host "Setup paused. You can run deployment later with: powershell automation/azure_deploy.ps1" -ForegroundColor Yellow
}