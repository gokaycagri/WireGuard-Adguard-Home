# Configuration Logic Unit Test - Advanced DevOps Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
$YAML_FILE = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"

function Show-Test { param($Name, $Passed) 
    if ($Passed) { Write-Host "[PASS] $Name" -ForegroundColor Green }
    else { Write-Host "[FAIL] $Name" -ForegroundColor Red }
}

Write-Host "--- Running Advanced Configuration Suite ---" -ForegroundColor Cyan

if (-not (Test-Path $YAML_FILE)) { 
    Write-Host "No config file found to test!" -ForegroundColor Yellow
    exit 1
}

$content = Get-Content $YAML_FILE -Raw

# 1. Structural integrity
Show-Test "Valid Cloud-Init header" ($content.StartsWith("#cloud-config"))
Show-Test "No unreplaced placeholders" (-not ($content.Contains("{{VPN_B64}}") -or $content.Contains("{{AG_B64}}")))

# 2. IP Collision Prevention
$ips = [regex]::Matches($content, 'ipv4_address: (172\.20\.0\.\d+)') | ForEach-Object { $_.Groups[1].Value }
$uniqueIps = $ips | Select-Object -Unique
Show-Test "No internal IP collisions ($($uniqueIps.Count) unique IPs)" ($ips.Count -eq $uniqueIps.Count)

# 3. Mount Point Verification
Show-Test "WireGuard persistent storage" ($content.Contains("./wg-easy:/etc/wireguard"))
Show-Test "AdGuard persistent storage" ($content.Contains("./adguard/work:/opt/adguardhome/work"))
Show-Test "Docker socket exposure" ($content.Contains("/var/run/docker.sock:/var/run/docker.sock"))

# 4. Service Logic Validation
Show-Test "DNS Rewrite rule present" ($content.Contains("rewrites:") -and $content.Contains("enabled: true"))
Show-Test "Caddy basic_auth present" ($content.Contains("basic_auth {"))
Show-Test "Caddy Host headers present" ($content.Contains("header_up Host {host}"))

# 5. Shell Script Integrity
$catStartCount = ([regex]::Matches($content, 'cat <<EOF')).Count + ([regex]::Matches($content, "cat <<'EOF'")).Count
$catEndCount = ([regex]::Matches($content, '^      EOF', 'Multiline')).Count
Show-Test "Heredoc (cat <<EOF) block integrity" ($catStartCount -eq $catEndCount)

# 6. Critical Command Checks
Show-Test "IP Forwarding (Sysctl)" ($content.Contains("net.ipv4.ip_forward=1"))
Show-Test "NAT Masquerade" ($content.Contains("MASQUERADE"))
Show-Test "systemd-resolved disable" ($content.Contains("systemctl disable systemd-resolved"))

# 7. Formatting & Indentation
$lines = Get-Content $YAML_FILE
$badIndent = @()
$inBlock = $false
foreach ($line in $lines) {
    if ($line -match "content: \|") { $inBlock = $true; continue }
    # End of a literal block (new list item or root key)
    if ($inBlock -and ($line -match "^  - path:" -or $line -match "^[^\s]")) { $inBlock = $false }
    
    if ($inBlock -and $line.Trim().Length -gt 0) {
        if ($line -notmatch "^\s{6}") {
            $badIndent += $line
        }
    }
}
Show-Test "YAML Block Indentation (min 6 spaces)" ($badIndent.Count -eq 0)

if ($badIndent.Count -gt 0) {
    Write-Host "`n--- FAILED LINES ---" -ForegroundColor Yellow
    $badIndent | ForEach-Object { Write-Host ">$_<" -ForegroundColor Gray }
}

Write-Host "`n--- Tests Complete ---" -ForegroundColor Cyan
if ($badIndent.Count -gt 0 -or ($catStartCount -ne $catEndCount)) { exit 1 }