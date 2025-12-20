# Azure WireGuard & AdGuard Home VPN (Pro Edition)

Deploy a hardened, automated, and secure VPN server on Microsoft Azure in minutes.

## Features
*   **One-Click Setup:** Unified interactive CLI for all operations.
*   **Security Hardened:** Kernel-level hardening, Fail2Ban, and IP-locked management.
*   **Geo-Blocking:** Restrict server access to your specific country (e.g., TR, US).
*   **Auto-Maintenance:** Watchtower automatically keeps your VPN and DNS software updated.
*   **Full HTTPS:** Automatic SSL for all web interfaces using `sslip.io`.

## Prerequisites
Before starting, ensure your system is ready:
```powershell
powershell automation/check_requirements.ps1
```
*   **Azure CLI:** Installed and logged in (`az login`).
*   **SSH Key:** Generated at `~/.ssh/id_rsa.pub`.

## Deployment Guide

### 1. Launch the Setup
Run the interactive setup script from the project root:
```powershell
powershell ./setup.ps1
```

### 2. Enter Configuration
The script will prompt you for:
*   **Resource Group & VM Name:** Customize your Azure resource names.
*   **Azure Region:** Choose the closest location (e.g., `northeurope`).
*   **Allowed Country:** Enter your ISO country code (e.g., `TR`) to block all other global traffic.
*   **Passwords:** Set unique passwords for the WireGuard and AdGuard dashboards.

### 3. Automatic Deployment
Confirm deployment by entering `y`. The script will:
1.  Provision the Azure VM.
2.  Lock SSH and Web access to your current Public IP.
3.  Configure HTTPS and SSL certificates automatically.

## Accessing Your VPN
Once the script finishes, it will display your secure links:
*   **AdGuard Home:** `https://adguard.<SERVER_IP>.sslip.io`
*   **WireGuard UI:** `https://vpn.<SERVER_IP>.sslip.io`

**Credentials:**
*   **User:** `admin` (AdGuard)
*   **Password:** *The passwords you set during setup.*

## Maintenance

### SSL Certificate Renewal
SSL certificates are automatically managed by Caddy but require port 80 to be open. Since we lock this port to your IP for security, you should run this command every ~80 days (or if you see SSL errors):
```powershell
powershell automation/renew_ssl.ps1
```

### Verify Status
Check if services are running:

### Deleting the System
To remove all Azure resources and stop billing:
```powershell
powershell automation/azure_destroy.ps1
```

## Security Warning
The management ports (SSH, HTTPS) are **locked to your specific IP address** at the time of deployment. If your home/office IP changes, you will need to update the Network Security Group (NSG) in the Azure Portal to regain access.
