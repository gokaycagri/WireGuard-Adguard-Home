# Project Context: Azure WireGuard & AdGuard Home VPN (Hardened Pro Edition)

## Project Overview
This project is a high-security, professional deployment solution for a personal VPN on Microsoft Azure. It integrates **WireGuard** for high-performance tunneling and **AdGuard Home** for network-wide DNS ad-blocking. The system is hardened at the OS and network layers and optimized for Azure's economic B-series VMs.

## Key Features
*   **Unified CLI Setup:** A single command (`setup.ps1`) manages the entire lifecycle.
*   **RAM Optimization:** Automatic 2GB Swap file creation to ensure stability on 1GB RAM VMs.
*   **Existing VNet Support:** Option to deploy into an existing Azure Virtual Network or create a new one.
*   **Security Lockdown:** Automated firewall management that opens ports for SSL validation and then locks them to the Admin's IP.
*   **Auto-Maintenance:** Integrated **Watchtower** for automatic software updates.
*   **Hardened OS:** Includes Fail2Ban, kernel network hardening, and disabled password authentication.
*   **Full HTTPS:** Secure web access via Caddy and Let's Encrypt using `sslip.io`.

## Architecture
*   **Infrastructure:** Ubuntu 24.04 LTS on Azure, Static IP, Dynamic NSG.
*   **Networking:** Isolated Docker network (`172.20.0.0/24`).
*   **WireGuard Optimized:** MTU 1420, PersistentKeepalive, and forced DNS via AdGuard.

## Workflow
1.  Run `powershell ./setup.ps1`.
2.  Input Azure resources, network preferences, and passwords.
3.  The system deploys, configures HTTPS, and locks down the firewall automatically.
4.  Maintenance (SSL renewal) is handled via `automation/renew_ssl.ps1`.