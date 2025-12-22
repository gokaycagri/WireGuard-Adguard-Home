# Professional VPN Setup CLI - Clean Code Edition
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\automation\lib.ps1"

Clear-Host
Show-Header "AZURE VPN & ADGUARD HOME INSTALLER"

# 1. Pre-Flight Checks
Show-Step "Verifying system requirements..."
& "$ScriptDir\automation\check_requirements.ps1"

# 2. Configuration Gathering
Show-Header "CONFIGURATION"

$ResourceGroup = Read-Host "  Enter Resource Group Name [VPN-RS]"
if (-not $ResourceGroup) { $ResourceGroup = "VPN-RS" }

$VmName = Read-Host "  Enter Virtual Machine Name [VPN-VM]"
if (-not $VmName) { $VmName = "VPN-VM" }

$Region = Read-Host "  Enter Azure Region [northeurope]"
if (-not $Region) { $Region = "northeurope" }

$AdminUser = Read-Host "  Enter Admin Username [azureuser]"
if (-not $AdminUser) { $AdminUser = "azureuser" }

$VNetName = Read-Host "  Enter Existing VNet Name (Leave empty to create new)"
$SubnetName = ""
if ($VNetName) {
    $SubnetName = Read-Host "  Enter Subnet Name for this VNet"
}

Write-Host "`n  --- Security ---" -ForegroundColor Yellow
$DashboardUser = Read-Host "  Set Dashboard Username [admin]"
if (-not $DashboardUser) { $DashboardUser = "admin" }

$VpnPassword = Read-Host "  Set WireGuard Web Password"
$AdGuardPassword = Read-Host "  Set Dashboard Password (AdGuard, SpeedTest, Glances)"

# 3. Save Configuration
Show-Step "Saving settings to config.yaml..."
$ConfigTemplate = @"
azure:
  resource_group: "$ResourceGroup"
  location: "$Region"
  vm_name: "$VmName"
  vm_size: "Standard_B1s"
  admin_user: "$AdminUser"
  vnet_name: "$VNetName"
  subnet_name: "$SubnetName"
server:
  ip: "0.0.0.0"
adguard:
  username: "$DashboardUser"
  upstream_dns: ["https://dns.cloudflare.com/dns-query", "tls://1.1.1.1"]
  blocklists: ["https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"]
"@
Set-Content -Path "$ScriptDir\automation\config.yaml" -Value $ConfigTemplate

# 4. Generate Cloud-Init
Show-Step "Generating server configuration..."
$VpnPassword, $AdGuardPassword | & "$ScriptDir\automation\generate_cloud_init.ps1" | Out-Null

# 4.1 Run Pre-Flight Configuration Tests
Show-Step "Running configuration unit tests..."
& "$ScriptDir\automation\test_config.ps1"
if ($LASTEXITCODE -ne 0) {
    Show-Error "Configuration validation failed. Aborting."
    exit 1
}
Show-Success "Configuration valid."

# 5. Deployment Confirmation
$Choice = Read-Host "`nDo you want to deploy to Azure now? (y/n)"
if ($Choice -eq "y") {
    Show-Header "DEPLOYMENT STARTED"
    & "$ScriptDir\automation\azure_deploy.ps1"
    
    # Reload Config to get updated IP
    $Config = Get-VpnConfig
    $ServerIp = $Config.server.ip
    
    Show-Step "Waiting for server initialization (120s)..."
    Start-Sleep -Seconds 120
    
    # 5.1 Post-Deployment Health Check
    Show-Step "Verifying server health..."
    & "$ScriptDir\automation\verify_deployment.ps1" -ServerIp $ServerIp
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[WARNING] Health check reported issues. Please check logs above." -ForegroundColor Yellow
        $Continue = Read-Host "Continue with HTTPS setup? (y/n)"
        if ($Continue -ne "y") { exit }
    }

    Show-Step "Finalizing HTTPS..."
    & "$ScriptDir\automation\configure_https.ps1" -ServerIp $ServerIp
    
    # Automated SSL Verification Loop
    Show-Step "Waiting for SSL certificates to be issued (this may take up to 2 minutes)..."
    $maxRetries = 24 # 2 minutes (5s interval)
    $sslReady = $false
    
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            # Try to fetch the AdGuard login page securely
            $request = Invoke-WebRequest -Uri "https://adguard.$ServerIp.sslip.io" -UseBasicParsing -ErrorAction Stop
            if ($request.StatusCode -eq 200) {
                $sslReady = $true
                Show-Success "SSL Verification Successful!"
                break
            }
        } catch {
            Write-Host -NoNewline "."
            Start-Sleep -Seconds 5
        }
    }

    if (-not $sslReady) {
        Show-Error "SSL verification timed out. Firewall will NOT be locked down automatically."
        Show-Error "Please verify via browser and run 'automation/renew_ssl.ps1' later."
    } else {
        Show-Step "Applying security lockdown (IP restricted access)..."
        try {
            $AdminIp = Get-PublicIp
            $NsgName = Get-AzureNsgName -ResourceGroup $ResourceGroup -VmName $VmName

            if ($NsgName) {
                Show-Step "Locking down NSG: $NsgName to $AdminIp"
                az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowSSH --source-address-prefixes $AdminIp --output none
                az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTP --source-address-prefixes $AdminIp --output none
                az network nsg rule update -g $ResourceGroup --nsg-name $NsgName --name AllowHTTPS --source-address-prefixes $AdminIp --output none
                Show-Success "Firewall restricted."
            } else {
                Show-Error "Could not detect NSG name. Please lock down manually."
            }
        } catch {
            Show-Error "Lockdown failed. Error: $_"
        }
    }

    Show-Success "Installation Complete!"
    Write-Host "`nDashboards are now accessible at:" -ForegroundColor Cyan
    Write-Host "VPN:       https://vpn.$ServerIp.sslip.io" -ForegroundColor White
    Write-Host "AdGuard:   https://adguard.$ServerIp.sslip.io" -ForegroundColor White
    Write-Host "SpeedTest: https://speed.$ServerIp.sslip.io" -ForegroundColor White
    Write-Host "Glances:   https://glances.$ServerIp.sslip.io" -ForegroundColor White
    
    Write-Host "`n--- MAINTENANCE NOTICE ---" -ForegroundColor Yellow
    Write-Host "SSL certificates expire every 90 days. Run:" -ForegroundColor Gray
    Write-Host "powershell automation/renew_ssl.ps1" -ForegroundColor Cyan
} else {
    Write-Host "`nSetup paused. Run 'automation/azure_deploy.ps1' to resume." -ForegroundColor Yellow
}
