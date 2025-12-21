# VPN Automation Shared Library - Enterprise Edition
$ErrorActionPreference = "Stop"

function Get-VpnConfig {
    $configFile = "$PSScriptRoot\config.yaml"
    if (-not (Test-Path $configFile)) { return $null }
    
    $config = @{ azure = @{}; adguard = @{}; server = @{} }
    $lines = Get-Content $configFile
    $section = ""

    foreach ($line in $lines) {
        if ($line -match "^(\w+)\s*:") { 
            $section = $Matches[1].ToLower()
            continue 
        }
        if ($section -and ($line -match "^\s+(\w+)\s*:\s*(.*)")) {
            $key = $Matches[1].ToLower()
            $val = $Matches[2].Trim()
            $val = $val -replace "^['`"]", "" -replace "['`"]$", ""
            if ($key) { $config[$section][$key] = $val }
        }
    }
    return $config
}

function Get-PublicIp {
    $services = @("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com")
    foreach ($service in $services) {
        try {
            $ip = (Invoke-RestMethod -Uri $service -TimeoutSec 5 -ErrorAction Stop).Trim()
            if ($ip -match "^\d{1,3}(\.\d{1,3}){3}$") { return $ip }
        } catch { continue }
    }
    throw "Could not detect Public IP. Check internet connection."
}

function Get-AzureNsgName {
    param([string]$Rg, [string]$Vm)
    try {
        $nicId = az vm show -g $Rg -n $Vm --query "networkProfile.networkInterfaces[0].id" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($nicId)) { return $null }
        
        $nsgId = az network nic show --id $nicId --query "networkSecurityGroup.id" -o tsv 2>$null
        if ([string]::IsNullOrWhiteSpace($nsgId)) { return $null }
        
        return ($nsgId -split "/")[-1]
    } catch { return $null }
}

function Show-Header {
    param([string]$Title)
    $line = "=" * ($Title.Length + 4)
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$line`n" -ForegroundColor Cyan
}

function Show-Step { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Gray }
function Show-Success { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Show-Error { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }