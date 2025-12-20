# VPN Project Requirements Checker
$ErrorActionPreference = "Continue"

Write-Host "--- Checking System Requirements ---" -ForegroundColor Cyan

$allPassed = $true

# 1. Azure CLI Check
Write-Host "[1/3] Checking Azure CLI..." -NoNewline
if (Get-Command "az" -ErrorAction SilentlyContinue) {
    $azVer = az --version | Select-String "azure-cli"
    Write-Host " [OK] ($($azVer.ToString().Trim()))" -ForegroundColor Green
    
    # Check if logged in
    try {
        $account = az account show --query name -o tsv 2>$null
        if ($null -ne $account) {
            Write-Host "      Logged in as: $account" -ForegroundColor Gray
        } else {
            Write-Host "      WARNING: Not logged in. Run 'az login' before deploying." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "      WARNING: Not logged in. Run 'az login' before deploying." -ForegroundColor Yellow
    }
} else {
    Write-Host " [FAILED]" -ForegroundColor Red
    Write-Host "      Azure CLI not found. Install it from: https://aka.ms/installazurecliwindows" -ForegroundColor Gray
    $allPassed = $false
}

# 2. OpenSSH Check
Write-Host "[2/3] Checking OpenSSH Client..." -NoNewline
if (Get-Command "ssh" -ErrorAction SilentlyContinue) {
    Write-Host " [OK]" -ForegroundColor Green
} else {
    Write-Host " [FAILED]" -ForegroundColor Red
    Write-Host "      SSH client not found. On Windows, enable 'OpenSSH Client' in Optional Features." -ForegroundColor Gray
    $allPassed = $false
}

# 3. SSH Key Check
Write-Host "[3/3] Checking SSH Keys..." -NoNewline
$sshKeyPath = "$HOME\.ssh\id_rsa.pub"
if (Test-Path $sshKeyPath) {
    Write-Host " [OK] ($sshKeyPath)" -ForegroundColor Green
} else {
    Write-Host " [MISSING]" -ForegroundColor Yellow
    Write-Host "      No SSH public key found. Run 'ssh-keygen -t rsa -b 4096' to create one." -ForegroundColor Gray
    $allPassed = $false
}

Write-Host "------------------------------------"
if ($allPassed) {
    Write-Host "STATUS: Your system is READY for deployment." -ForegroundColor Green
} else {
    Write-Host "STATUS: Some requirements are missing. Please fix them before proceeding." -ForegroundColor Red
}
