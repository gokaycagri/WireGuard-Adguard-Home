# Professional VPN Setup CLI - Robust Lockdown
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

$adminUser = Read-Host "  Enter Admin Username [azureuser]"
if (!$adminUser) { $adminUser = "azureuser" }

$VNet = Read-Host "  Enter Existing VNet Name (Leave empty to create new)"
$Subnet = ""
if ($VNet) {
    $Subnet = Read-Host "  Enter Subnet Name for this VNet"
}

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
  admin_user: "$adminUser"
  vnet_name: "$VNet"
  subnet_name: "$Subnet"
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
    
    # Reload config to get the Server IP
    $config = Get-VpnConfig
    $ServerIp = $config.server.ip
    $RG = $config.azure.resource_group
    $VM = $config.azure.vm_name

    Show-Step "Waiting for server initialization (60s)..."
    Start-Sleep -Seconds 60
    
    Show-Step "Finalizing HTTPS..."
    & "$SCRIPT_DIR\automation\configure_https.ps1" -ServerIp $ServerIp
    
    Show-Step "Applying security lockdown (IP restricted access)..."
    $AdminIp = (Invoke-RestMethod -Uri "https://api.ipify.org").Trim()
    
    # Dynamically find the NSG Name from VM details
    Show-Step "Detecting Network Security Group name..."
    $nicId = az vm show -g $RG -n $VM --query "networkProfile.networkInterfaces[0].id" -o tsv
    $nsgId = az network nic show --id $nicId --query "networkSecurityGroup.id" -o tsv
    $nsgName = ($nsgId -split "/")[-1]

    if ($nsgName) {
        Show-Step "Locking down NSG: $nsgName"
        az network nsg rule update -g $RG --nsg-name $nsgName --name AllowSSH --source-address-prefixes $AdminIp --output none
        az network nsg rule update -g $RG --nsg-name $nsgName --name AllowHTTP --source-address-prefixes $AdminIp --output none
        az network nsg rule update -g $RG --nsg-name $nsgName --name AllowHTTPS --source-address-prefixes $AdminIp --output none
        Show-Success "Firewall restricted to $AdminIp."
    } else {
        Show-Error "Could not detect NSG name. Management ports remain open."
    }

    Show-Success "Installation Complete!"
    Write-Host "`nDashboards are now accessible at:" -ForegroundColor Cyan
    Write-Host "VPN:     https://vpn.$ServerIp.sslip.io" -ForegroundColor White
    Write-Host "AdGuard: https://adguard.$ServerIp.sslip.io" -ForegroundColor White
    
    Write-Host "`n--- MAINTENANCE NOTICE ---" -ForegroundColor Yellow
    Write-Host "SSL certificates expire every 90 days. Run:" -ForegroundColor Gray
    Write-Host "powershell automation/renew_ssl.ps1" -ForegroundColor Cyan
} else {
    Write-Host "`nSetup paused. Run 'automation/azure_deploy.ps1' to resume." -ForegroundColor Yellow
}