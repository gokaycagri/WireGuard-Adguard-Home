# Professional VPN Setup CLI - Beautified
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\automation\lib.ps1"

Clear-Host
Show-Header "AZURE VPN & ADGUARD HOME INSTALLER"

# 1. Check Requirements
Show-Step "Verifying system requirements..."
& "$SCRIPT_DIR\automation\check_requirements.ps1"

# 2. Collect Information
Show-Header "CONFIGURATION"

$RG      = Read-Host "  Enter Resource Group Name [VPN-RS]"
if (!$RG) { $RG = "VPN-RS" }

$VM      = Read-Host "  Enter Virtual Machine Name [VPN-VM]"
if (!$VM) { $VM = "VPN-VM" }

$Region  = Read-Host "  Enter Azure Region [northeurope]"
if (!$Region) { $Region = "northeurope" }

$Country = Read-Host "  Enter Your Country Code (e.g. TR, US) [TR]"
if (!$Country) { $Country = "TR" }

Write-Host "`n  --- Security ---" -ForegroundColor Yellow
$VpnPass = Read-Host "  Set WireGuard Web Password"
$AgPass  = Read-Host "  Set AdGuard Admin Password"

# 3. Save Config
Show-Step "Saving settings to config.yaml..."
$configTemplate = @"
azure:
  resource_group: "$RG"
  location: "$Region"
  vm_name: "$VM"
  vm_size: "Standard_B1s"
  admin_user: "azureuser"
  allowed_country: "$($Country.ToUpper())"
server:
  ip: "0.0.0.0"
adguard:
  username: "admin"
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "tls://1.1.1.1"]
  blocklists: ["https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"]
"@
Set-Content -Path "$SCRIPT_DIR\automation\config.yaml" -Value $configTemplate

# 4. Generate Cloud-Init
Show-Step "Generating server configuration..."
"$VpnPass`n$AgPass" | & "$SCRIPT_DIR\automation\generate_cloud_init.ps1" | Out-Null
Show-Success "Deployment files ready."

# 5. Deployment
$choice = Read-Host "`nDo you want to deploy to Azure now? (y/n)"
if ($choice -eq "y") {
    Show-Header "DEPLOYMENT STARTED"
    & "$SCRIPT_DIR\automation\azure_deploy.ps1"
    
    $config = Get-VpnConfig
    $ServerIp = $config.server.ip

    Show-Step "Waiting for server initialization (60s)..."
    Start-Sleep -Seconds 60
    
    Show-Step "Finalizing HTTPS..."
    & "$SCRIPT_DIR\automation\configure_https.ps1" -ServerIp $ServerIp
    
    Show-Step "Applying security lockdown (IP restricted access)..."
    $AdminIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    $NSG = "$($config.azure.vm_name)NSG"
    $RG  = $config.azure.resource_group
    
    az network nsg rule update -g $RG --nsg-name $NSG --name AllowSSH --source-address-prefixes $AdminIp --output none
    az network nsg rule update -g $RG --nsg-name $NSG --name AllowHTTP --source-address-prefixes $AdminIp --output none
    az network nsg rule update -g $RG --nsg-name $NSG --name AllowHTTPS --source-address-prefixes $AdminIp --output none

    Show-Success "Installation Complete!"
    Write-Host "`nDashboards are now accessible at:" -ForegroundColor Cyan
    Write-Host "VPN:     https://vpn.$ServerIp.sslip.io" -ForegroundColor White
    Write-Host "AdGuard: https://adguard.$ServerIp.sslip.io" -ForegroundColor White
} else {
    Write-Host "`nSetup paused. Run 'automation/azure_deploy.ps1' to resume." -ForegroundColor Yellow
}
