# Config Deployer (Rescue)
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

$config = Get-VpnConfig
$ServerIp = $config.server.ip

Show-Header "RESCUE DEPLOYMENT"
Show-Step "Target: $ServerIp"

# 1. Extract the setup script content from cloud-init yaml
$yamlPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
if (-not (Test-Path $yamlPath)) { Show-Error "Cloud-init file not found."; exit }

$content = Get-Content $yamlPath -Raw
# Regex to capture the setup.sh content block
if ($content -match 'path: /root/setup.sh[\s\S]*?content: \|\n([\s\S]*?)\nruncmd:') {
    $scriptContent = $Matches[1]
    # Remove YAML indentation (6 spaces)
    $cleanScript = $scriptContent -replace '(?m)^      ', ''
    
    # Save temp file
    $tempFile = Join-Path $env:TEMP "rescue_setup.sh"
    Set-Content -Path $tempFile -Value $cleanScript -Encoding UTF8
    
    # Upload and Run
    Show-Step "Uploading configuration script..."
    scp -o StrictHostKeyChecking=no $tempFile azureuser@${ServerIp}:/tmp/rescue_setup.sh
    
    Show-Step "Executing setup..."
    ssh -o StrictHostKeyChecking=no azureuser@${ServerIp} "chmod +x /tmp/rescue_setup.sh; sudo /tmp/rescue_setup.sh"
    
    Show-Success "Configuration deployed."
} else {
    Show-Error "Could not parse cloud-init file."
}
