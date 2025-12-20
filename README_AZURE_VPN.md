# Azure WireGuard & AdGuard Home VPN (Automated)

A fully automated, secure, and ad-blocking VPN solution for Microsoft Azure.

## Features
*   **WireGuard:** Fast and modern VPN protocol.
*   **AdGuard Home:** Network-wide ad blocking and tracking protection.
*   **HTTPS (TLS):** Secure web access using Caddy and Let's Encrypt (via `sslip.io` Magic DNS).
*   **Secure:** Management ports (SSH, Web UI) are automatically locked to your IP address.
*   **Automated:** Deployed with a single PowerShell script.

## Prerequisites
1.  **Azure CLI:** Installed and logged in (`az login`).
2.  **PowerShell:** Core or Windows PowerShell.
3.  **OpenSSH:** Key pair generated (`~/.ssh/id_rsa`).

## Quick Start

### 1. Configuration
Check `automation/config.yaml`. Default password is `password`.
To generate the necessary cloud-init files:
```powershell
powershell automation/generate_cloud_init.ps1
```

### 2. Deploy to Azure
This script creates the Resource Group, VM, and configures the Firewall (NSG).
It automatically detects your Public IP to restrict management access.
```powershell
powershell automation/azure_deploy.ps1
```
*Take note of the Public IP address displayed at the end.*

### 3. Update Config
Update `automation/config.yaml` with the new Server IP address.

### 4. Enable HTTPS
Configure Caddy to serve the Web UIs securely over HTTPS.
```powershell
powershell automation/configure_https.ps1
```

### 5. Access
Your services are now available at:
*   **AdGuard Home:** `https://adguard.<SERVER_IP>.sslip.io`
*   **WireGuard UI:** `https://vpn.<SERVER_IP>.sslip.io`

**Default Credentials:**
*   **User:** `admin` (AdGuard)
*   **Password:** `password` (Both)

## Maintenance

### Verify Status
Check if services are running:
```powershell
powershell automation/verify_deployment.ps1
```

### Destroy System
To delete everything (VM, IP, Disk, Resource Group):
```powershell
powershell automation/azure_destroy.ps1
```

## Security Note
The deployment script locks SSH (22), HTTP (80), and HTTPS (443) ports to the IP address of the machine running the script.
**If your IP changes**, you will lose access. You must manually update the Network Security Group (NSG) rules in the Azure Portal.
The VPN port (UDP 51820) remains open globally to allow connections from anywhere.