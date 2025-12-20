# Hardened Azure VPN with AdGuard Home

A professional, automated deployment of WireGuard and AdGuard Home on Microsoft Azure.

## Features
*   **Performance:** Optimized MTU and Keepalive settings for stable mobile connections.
*   **Security:** OS hardening, Fail2Ban, and IP-restricted management ports.
*   **Stability:** Automatic 2GB Swap space for reliable operation on small VMs.
*   **Flexibility:** Deploy into new or existing Azure VNets.
*   **Privacy:** Ad-blocking DNS integration with encrypted upstream queries.

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
3.  **Network Setup:** Specify an existing VNet or leave blank to create a new one.
4.  **Dashboards:** Set your passwords for the Web UIs.
5.  **Deployment:** Confirm with `y` to begin the automated process.

## Access
Once complete, use these secure links:
*   **AdGuard Home:** `https://adguard.<IP>.sslip.io` (User: `admin`)
*   **WireGuard UI:** `https://vpn.<IP>.sslip.io`

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

## Troubleshooting
If you cannot access the dashboards, ensure your **current Public IP** matches the one recorded during deployment. You can update the NSG rules in the Azure Portal if your local IP has changed.