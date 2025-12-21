# Ultimate Azure VPN with AdGuard, SpeedTest & Monitoring

A professional, automated deployment of a complete VPN and Server Management stack on Microsoft Azure.

## Features
*   **VPN Tunnel:** WireGuard with optimized MTU and Keepalive settings.
*   **Ad Blocking:** AdGuard Home with DoH/DoT encrypted upstream DNS.
*   **Speed Test:** OpenSpeedTest for measuring VPN bandwidth.
*   **Monitoring:** Glances for real-time server health stats (CPU/RAM).
*   **Security:** OS hardening, Fail2Ban, IP-restricted management ports, and Production SSL.
*   **Stability:** Automatic 2GB Swap space for reliable operation on small VMs.

## Prerequisites
Ensure your local machine is ready:
```powershell
powershell automation/check_requirements.ps1
```
*   **Azure CLI:** Logged in via `az login`.
*   **SSH Key:** Public key found at `~/.ssh/id_rsa.pub`.

## Installation

1.  **Start the Setup:**
    ```powershell
    powershell ./setup.ps1
    ```
2.  **Follow the Prompts:** Enter your Resource Group, VM Name, and desired Region.
3.  **Dashboards:** Set your passwords.
4.  **Deployment:** Confirm with `y` to begin the automated process.

## Access
Once complete, use these secure links:
*   **WireGuard UI:** `https://vpn.<IP>.sslip.io`
*   **AdGuard Home:** `https://adguard.<IP>.sslip.io`
*   **SpeedTest:** `https://speed.<IP>.sslip.io`
*   **Glances:** `https://glances.<IP>.sslip.io`

> **User:** `admin` (AdGuard)

## Maintenance

### SSL Renewal
Every ~80 days, run this to renew certificates (since ports are IP-locked):
```powershell
powershell automation/renew_ssl.ps1
```

### Full Destruction
To delete all Azure resources:
```powershell
powershell automation/azure_destroy.ps1
```
