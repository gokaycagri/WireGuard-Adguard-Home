# Configuration Logic Unit Test - Ultimate Stable Edition
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

# Test 3: AdGuard Port Mapping (Must be 53:53)
Show-Test "AdGuard Port Mapping (53:53)" ($content.Contains("53:53/udp"))

# Test 4: Caddy BasicAuth Check (Checking for basic_auth directive)
Show-Test "Caddy basic_auth protection exists" ($content.Contains("basic_auth {"))

# Test 5: AdGuard DNS Rewrites
Show-Test "AdGuard DNS Rewrite rule exists" ($content.Contains("rewrites:"))

# Test 6: Docker Container Presence
Show-Test "WireGuard included" ($content.Contains("wg-easy:"))
Show-Test "AdGuard included" ($content.Contains("adguardhome:"))
Show-Test "SpeedTest included" ($content.Contains("speedtest:"))
Show-Test "Glances included" ($content.Contains("glances:"))

# Test 7: Indentation
$lines = Get-Content $YAML_FILE
$setupBlockFound = $false
$indentError = $false
foreach ($line in $lines) {
    if ($line -match "path: /root/setup.sh") { $setupBlockFound = $true; continue }
    if ($setupBlockFound -and $line -match "^runcmd:") { $setupBlockFound = $false }
    if ($setupBlockFound -and $line.Trim().Length -gt 0 -and $line -match "^[^\s]" -and -not ($line -match "path:|permissions:|content:")) {
        $indentError = $true
    }
}
Show-Test "Cloud-Init Indentation Integrity" (-not $indentError)

Write-Host "--- Tests Complete ---" -ForegroundColor Cyan
if ($indentError) { exit 1 }
