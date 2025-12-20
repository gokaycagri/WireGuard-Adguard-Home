# Azure System Destruction Script (PowerShell)
$ErrorActionPreference = "Stop"

# --- Shared Utilities ---
$SCRIPT_DIR = $PSScriptRoot
$CONFIG_FILE = "$SCRIPT_DIR\config.yaml"

# Simplified Config Reader
function Get-ConfigValue {
    param ([string]$Section, [string]$Key)
    $lines = Get-Content $CONFIG_FILE
    $inSection = $false
    foreach ($line in $lines) {
        if ($line -match "^$Section\s*:") {
            $inSection = $true
            continue
        }
        if ($inSection -and $line -match "^\w+\s*:") {
            $inSection = $false
        }
        if ($inSection -and $line -match "^\s+$Key\s*:\s*[`"']?([^`"']+)`?['`"]?") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

# 1. Load Configuration
if (-not (Test-Path $CONFIG_FILE)) { Write-Error "Config file not found!" }
$RESOURCE_GROUP = Get-ConfigValue -Section "azure" -Key "resource_group"

if (-not $RESOURCE_GROUP) { Write-Error "Could not read Resource Group from config!" }

Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
Write-Host "WARNING: This operation will delete ALL resources in '$RESOURCE_GROUP'." -ForegroundColor Red
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red

$confirm = Read-Host "Do you want to continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit
}

# 2. Azure Login Check
Write-Host "[*] Checking Azure login..." -ForegroundColor Cyan
try { az account show | Out-Null } catch { az login }

# 3. Deletion
Write-Host "[*] Deleting Resource Group ($RESOURCE_GROUP)..." -ForegroundColor Cyan
az group delete --name $RESOURCE_GROUP --yes --no-wait

Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Deletion process started in background." -ForegroundColor Green
Write-Host "System is being removed..." -ForegroundColor Green
Write-Host "--------------------------------------------------" -ForegroundColor Green
