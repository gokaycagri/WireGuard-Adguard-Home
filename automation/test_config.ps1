# Configuration Logic Unit Test - Ultimate Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$YAML_FILE = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"

function Show-Test { param($Name, $Passed) 
    if ($Passed) { Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Name" -ForegroundColor Red }
}

Write-Host "--- Running Configuration Unit Tests ---" -ForegroundColor Cyan

if (-not (Test-Path $YAML_FILE)) { 
    Write-Host "No config file found to test! Run generate_cloud_init.ps1 first." -ForegroundColor Yellow
    exit 1
}

$content = Get-Content $YAML_FILE -Raw

# Test 1: YAML Structure
Show-Test "Starts with #cloud-config" ($content.StartsWith("#cloud-config"))

# Test 2: Placeholder Integrity
Show-Test "No unreplaced B64 placeholders" (-not ($content.Contains("{{VPN_B64}}") -or $content.Contains("{{AG_B64}}")))
Show-Test "No unreplaced User placeholders" (-not ($content.Contains("{{AG_USER}}")))

# Test 3: AdGuard Network Mode (Must be host)
Show-Test "AdGuard Host Network Mode" ($content.Contains("network_mode: host"))

# Test 4: Caddy BasicAuth Check
Show-Test "Caddy BasicAuth protection exists" ($content.Contains("basicauth {"))

# Test 5: Docker Container Presence
Show-Test "WireGuard included" ($content.Contains("wg-easy:"))
Show-Test "AdGuard included" ($content.Contains("adguardhome:"))
Show-Test "SpeedTest included" ($content.Contains("speedtest:"))
Show-Test "Glances included" ($content.Contains("glances:"))

# Test 6: Indentation (Critical)
$lines = Get-Content $YAML_FILE
$setupBlockFound = $false
$indentError = $false
foreach ($line in $lines) {
    if ($line -match "path: /root/setup.sh") { $setupBlockFound = $true; continue }
    if ($setupBlockFound -and $line -match "^runcmd:") { $setupBlockFound = $false }
    # Inside setup.sh, content should be indented at least 6 spaces
    if ($setupBlockFound -and $line.Trim().Length -gt 0 -and $line -match "^[^\s]" -and -not ($line -match "path:|permissions:|content:")) {
        $indentError = $true
    }
}
Show-Test "Cloud-Init Indentation Integrity" (-not $indentError)

Write-Host "--- Tests Complete ---" -ForegroundColor Cyan
if ($indentError) { exit 1 }