# VPN User Management CLI
# Connects to Azure VM and manages WireGuard users via API
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\automation\lib.ps1"

Clear-Host
Show-Header "VPN USER MANAGER"

# 1. Load Config & Validate
$Config = Get-VpnConfig
if (-not $Config) { exit }

$ServerIp = $Config.server.ip
if ($ServerIp -eq "0.0.0.0") {
    # Try to fetch real IP if config has placeholder
    try { $ServerIp = Get-PublicIp } catch { }
}

$AdminUser = $Config.azure.admin_user
$KeyPath = "~/.ssh/id_rsa"

Write-Host "Server: $ServerIp" -ForegroundColor Gray
Write-Host "User:   $AdminUser" -ForegroundColor Gray

# 2. Get VPN Password (Required for API)
$VpnPass = Read-Host "`nEnter WireGuard Web Password"
if ([string]::IsNullOrWhiteSpace($VpnPass)) { Show-Error "Password required."; exit }

# 3. Upload Helper Script
Show-Step "Connecting to server..."
$LocalScript = "$ScriptDir\automation\scripts\vpn_api.sh"
$RemoteScript = "/tmp/vpn_api.sh"

# SCP Upload (Using scp command directly for reliability)
$scpCommand = "scp -o StrictHostKeyChecking=no -i $KeyPath $LocalScript ${AdminUser}@${ServerIp}:${RemoteScript}"
Invoke-Expression $scpCommand 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Show-Error "Failed to connect to server. Check IP and SSH Key."
    exit
}

# Make executable
$sshBase = "ssh -o StrictHostKeyChecking=no -i $KeyPath ${AdminUser}@${ServerIp}"
Invoke-Expression "$sshBase 'chmod +x $RemoteScript'" | Out-Null

function Run-Remote-Api {
    param($Action, $Arg1 = "")
    $cmd = "$sshBase '$RemoteScript ""$VpnPass"" ""$Action"" ""$Arg1""'"
    $res = Invoke-Expression $cmd
    return $res
}

# 4. Interactive Menu
while ($true) {
    Clear-Host
    Show-Header "VPN USER MANAGER"
    Write-Host "1. List Users"
    Write-Host "2. Create New User"
    Write-Host "3. Get User Config (for QR/File)"
    Write-Host "4. Delete User"
    Write-Host "Q. Quit"
    
    $Choice = Read-Host "`nSelect Option"
    
    switch ($Choice) {
        "1" {
            Write-Host "`n--- Active Users ---" -ForegroundColor Cyan
            $users = Run-Remote-Api "list"
            if ($users -match "ERROR") { Write-Host $users -ForegroundColor Red }
            else {
                $users | ForEach-Object {
                    $parts = $_ -split " \| "
                    $status = if ($parts[3] -eq "true") { "[ACTIVE]" } else { "[DISABLED]" }
                    Write-Host "ID: $($parts[0]) - $($parts[1]) ($($parts[2])) $status"
                }
            }
            Read-Host "`nPress Enter to return to Main Menu..."
        }
        "2" {
            $Name = Read-Host "`nEnter Name for new user (e.g. Guest-Ahmed)"
            if ($Name) {
                Show-Step "Creating user..."
                $res = Run-Remote-Api "create" $Name
                if ($res -eq "OK") { 
                    Show-Success "User '$Name' created!"
                    Write-Host "Use Option 3 to get their config." -ForegroundColor Yellow
                } else {
                    Show-Error "Failed: $res"
                }
            }
            Read-Host "`nPress Enter to return to Main Menu..."
        }
        "3" {
            $Id = Read-Host "`nEnter User ID (from List)"
            if ($Id) {
                $conf = Run-Remote-Api "get" $Id
                if ($conf -match "Interface") {
                    $FileName = "vpn-config-$Id.conf"
                    Set-Content -Path $FileName -Value $conf
                    Show-Success "Saved to file: $FileName"
                    Write-Host "`n$conf" -ForegroundColor Gray
                } else {
                    Show-Error "Could not retrieve config. Check ID."
                }
            }
            Read-Host "`nPress Enter to return to Main Menu..."
        }
        "4" {
            $Id = Read-Host "`nEnter User ID to DELETE"
            if ($Id) {
                $confirm = Read-Host "Are you sure? (y/n)"
                if ($confirm -eq "y") {
                    Run-Remote-Api "delete" $Id
                    Show-Success "User deleted."
                }
            }
            Read-Host "`nPress Enter to return to Main Menu..."
        }
        "Q" {
            # Cleanup remote script
            Invoke-Expression "$sshBase 'rm -f $RemoteScript'" | Out-Null
            exit
        }
    }
}
