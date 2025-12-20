# VPN Automation Shared Library - Robust Version
$ErrorActionPreference = "Stop"

function Get-VpnConfig {
    $configFile = "$PSScriptRoot\config.yaml"
    if (-not (Test-Path $configFile)) { return $null }
    
    $config = @{ azure = @{}; adguard = @{}; server = @{} }
    $lines = Get-Content $configFile
    $section = ""

    foreach ($line in $lines) {
        # Match section headers (e.g., "azure:")
        if ($line -match "^(\w+)\s*:") { 
            $section = $Matches[1].ToLower()
            continue 
        }
        
        # Match key-value pairs (e.g., "  location: northeurope")
        # Handles optional quotes and captures everything after the colon
        if ($section -and ($line -match "^\s+(\w+)\s*:\s*(.*)")) {
            $key = $Matches[1].ToLower()
            $val = $Matches[2].Trim()
            
            # Strip surrounding quotes if present
            $val = $val -replace "^['`"]", "" -replace "['`"]$", ""
            
            # Only add if key is valid and value is not empty
            if ($key) {
                $config[$section][$key] = $val
            }
        }
    }
    return $config
}

function Show-Header {
    param([string]$Title)
    $line = "=" * ($Title.Length + 4)
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "$line`n" -ForegroundColor Cyan
}

function Show-Step {
    param([string]$Message)
    Write-Host "[*] $Message" -ForegroundColor Gray
}

function Show-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Show-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}