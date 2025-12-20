# Azure Removal Script - Beautified
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

$config = Get-VpnConfig
$RG = $config.azure.resource_group

Show-Header "REMOVING VPN SYSTEM"
Write-Host "  WARNING: This will delete ALL resources in '$RG'." -ForegroundColor Red
$confirm = Read-Host "`n  Confirm deletion? (yes/no)"

if ($confirm -eq "yes") {
    Show-Step "Terminating Azure Resource Group ($RG)..."
    az group delete --name $RG --yes --no-wait
    Show-Success "Removal process started in background."
} else {
    Write-Host "  Operation aborted." -ForegroundColor Yellow
}
