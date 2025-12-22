# Emergency Configuration Push
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

$config = Get-VpnConfig
$ServerIp = $config.server.ip

if (!$ServerIp) { Show-Error "Server IP not found."; exit }

Show-Header "EMERGENCY PUSH"
Show-Step "Target: $ServerIp"

# 1. Generate the setup script locally (simulated)
$VpnPass = Read-Host "Enter VPN Password"
$AgPass = Read-Host "Enter AdGuard Password"

echo "$VpnPass`n$AgPass" | & "$SCRIPT_DIR\generate_cloud_init.ps1" | Out-Null

# 2. Extract and Upload
$yamlPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
$content = Get-Content $yamlPath -Raw

if ($content -match 'path: /root/setup.sh[\s\S]*?content: \|\n([\s\S]*?)\nruncmd:') {
    $scriptContent = $Matches[1]
    $cleanScript = $scriptContent -replace '(?m)^      ', ''
    
    $tempFile = Join-Path $env:TEMP "emergency_setup.sh"
    Set-Content -Path $tempFile -Value $cleanScript -Encoding UTF8
    
    Show-Step "Uploading and executing setup..."
    scp -o StrictHostKeyChecking=no $tempFile azureuser@${ServerIp}:/tmp/setup.sh
    ssh -o StrictHostKeyChecking=no azureuser@${ServerIp} "chmod +x /tmp/setup.sh; sudo /tmp/setup.sh"
    
    Show-Success "Files restored. Now run: powershell automation/configure_https.ps1"
} else {
    Show-Error "Could not parse cloud-init file."
}
