# Requirements Check - Enterprise Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

Show-Header "SYSTEM PRE-FLIGHT CHECK"

# 1. Azure CLI
try {
    $azVer = az version --output json | ConvertFrom-Json
    Show-Success "Azure CLI: Installed (v$($azVer.'azure-cli'))"
} catch {
    Show-Error "Azure CLI not found. Please install it."
    exit 1
}

# 2. Azure Login
try {
    $account = az account show --output json | ConvertFrom-Json
    Show-Success "Azure Auth: Logged in as $($account.user.name)"
} catch {
    Show-Step "Please login to Azure..."
    az login --output none
    Show-Success "Azure Auth: Login successful"
}

# 3. SSH Client
try {
    $sshVer = ssh -V 2>&1
    if ($sshVer -match "OpenSSH") {
        Show-Success "SSH Client: OpenSSH found"
    } else {
        Show-Error "SSH Client: Unknown version ($sshVer)"
    }
} catch {
    Show-Error "SSH Client not found. Install OpenSSH."
}

# 4. SSH Keys
$keyPath = "$env:USERPROFILE\.ssh\id_rsa.pub"
if (Test-Path $keyPath) {
    Show-Success "SSH Key: Found at $keyPath"
} else {
    Show-Step "Generating SSH Key..."
    mkdir "$env:USERPROFILE\.ssh" -Force | Out-Null
    ssh-keygen -t rsa -b 4096 -f "$env:USERPROFILE\.ssh\id_rsa" -N ""
    Show-Success "SSH Key: Generated new keypair"
}

# 5. Git
try {
    git --version | Out-Null
    Show-Success "Git: Installed"
} catch {
    Show-Step "Git is recommended but not strictly required."
}

Write-Host "`nSystem is ready for deployment." -ForegroundColor Cyan