# VPN Server Verification Tool (PowerShell)

$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$ROOT_DIR = "$SCRIPT_DIR\.."
$CONFIG_FILE = "$ROOT_DIR\automation\config.yaml"

function Get-ServerIP {
    if (Test-Path $CONFIG_FILE) {
        $content = Get-Content $CONFIG_FILE -Raw
        # Capture IP key and value
        if ($content -match 'ip:\s*["'']?([0-9\.]+)["'']?') {
            return $Matches[1].Trim()
        }
    }
    return $null
}

function Check-SSH {
    param ([string]$Ip)
    Write-Host "[*] Checking SSH connection: $Ip..." -ForegroundColor Cyan
    try {
        # Timeout 5 seconds
        $result = ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 azureuser@$Ip "echo 'SSH OK'" 2>&1
        # Convert output to string (Powershell 2>&1 might return array)
        $resultStr = "$result"
        
        if ($resultStr -match "SSH OK") {
            Write-Host "   [OK] SSH Connection Successful." -ForegroundColor Green
            return $true
        } else {
            Write-Host "   [ERROR] SSH Failed or no response." -ForegroundColor Red
            # Write-Host "DEBUG: $resultStr" -ForegroundColor Gray
            return $false
        }
    } catch {
        Write-Host "   [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Check-Containers {
    param ([string]$Ip)
    Write-Host "[*] Checking Docker Containers..." -ForegroundColor Cyan
    $cmd = "sudo docker ps --format '{{.Names}}:{{.Status}}'"
    $result = ssh -o StrictHostKeyChecking=no azureuser@$Ip $cmd
    
    if ($result -match "wg-easy" -and $result -match "adguardhome") {
        Write-Host "   [OK] WireGuard and AdGuard Home are running." -ForegroundColor Green
        Write-Host "   Details:"
        Write-Host $result -ForegroundColor Gray
        return $true
    } else {
        Write-Host "   [ERROR] Containers are not running or missing." -ForegroundColor Red
        Write-Host $result -ForegroundColor Yellow
        return $false
    }
}

Write-Host "--- VPN Server Verification Tool ---" -ForegroundColor Yellow

$serverIp = Get-ServerIP

if (-not $serverIp) {
    $serverIp = Read-Host "Please enter the server IP address"
}

if (-not $serverIp) {
    Write-Host "IP address not provided. Exiting." -ForegroundColor Red
    exit
}

if (Check-SSH -Ip $serverIp) {
    if (Check-Containers -Ip $serverIp) {
        Write-Host "`n--- Deployment Summary ---" -ForegroundColor Green
        Write-Host "WireGuard Web UI: https://vpn.$serverIp.sslip.io"
        Write-Host "AdGuard Panel:    https://adguard.$serverIp.sslip.io"
        Write-Host "Verification complete." -ForegroundColor Green
    }
} else {
    Write-Host "`n[!] Cannot access the server. Please check IP address and SSH key." -ForegroundColor Red
}