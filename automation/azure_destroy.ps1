# Azure System Destruction Script (PowerShell)

$RESOURCE_GROUP = "MyVPN_Group"

Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
Write-Host "WARNING: This operation will delete ALL resources in '$RESOURCE_GROUP'." -ForegroundColor Red
Write-Host "This includes the VM, Static IP, Disks, and Network configuration." -ForegroundColor Red
Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red

$confirm = Read-Host "Do you want to continue? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
    exit
}

Write-Host "[1/2] Checking Azure login..." -ForegroundColor Cyan
try {
    az account show | Out-Null
} catch {
    Write-Host "Please login first:" -ForegroundColor Yellow
    az login
}

Write-Host "[2/2] Deleting Resource Group ($RESOURCE_GROUP)... This may take a few minutes." -ForegroundColor Cyan
az group delete --name $RESOURCE_GROUP --yes --no-wait

Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Deletion process started in background." -ForegroundColor Green
Write-Host "You can check status with 'az group show --name $RESOURCE_GROUP'." -ForegroundColor Green
Write-Host "System is being completely removed..." -ForegroundColor Green
Write-Host "--------------------------------------------------" -ForegroundColor Green