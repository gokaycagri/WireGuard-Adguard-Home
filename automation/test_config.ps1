# Configuration Logic Unit Test
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$YAML_FILE = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"

function Show-Test { param($Name, $Passed) 
    if ($Passed) { Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Name" -ForegroundColor Red }
}

Write-Host "--- Running Configuration Unit Tests ---" -ForegroundColor Cyan

if (-not (Test-Path $YAML_FILE)) { 
    Write-Host "No config file found to test!" -ForegroundColor Yellow
    exit 
}

$content = Get-Content $YAML_FILE -Raw

# Test 1: YAML Structure (Basic Check)
$isYaml = $content.StartsWith("#cloud-config")
Show-Test "Starts with #cloud-config" $isYaml

# Test 2: Placeholder Replacement
$hasPlaceholder = $content.Contains("{{VPN_B64}}") -or $content.Contains("{{AG_B64}}")
Show-Test "No unreplaced placeholders" (-not $hasPlaceholder)

# Test 3: Base64 Integrity
if ($content -match 'VPN_PASS=\$\(echo "(.*?)" \| base64 -d\)') {
    $b64 = $Matches[1]
    try {
        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
        Show-Test "Base64 Decoding ($decoded)" ($decoded -ne $null)
    } catch {
        Show-Test "Base64 Decoding" $false
    }
}

# Test 4: Indentation Check (Common Cloud-init killer)
$lines = Get-Content $YAML_FILE
$setupSection = $false
$badIndent = $false
foreach ($line in $lines) {
    if ($line -match "path: /root/setup.sh") { $setupSection = $true; continue }
    if ($setupSection -and $line -match "^runcmd:") { $setupSection = $false }
    if ($setupSection -and $line.Trim().Length -gt 0 -and $line -match "^[^\s]" -and -not ($line -match "path:|permissions:|content:")) {
        $badIndent = $true
    }
}
Show-Test "YAML Indentation integrity" (-not $badIndent)

Write-Host "--- Tests Complete ---" -ForegroundColor Cyan
