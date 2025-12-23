# Project Context: Azure WireGuard & AdGuard Home VPN (Ultimate Edition)

## Project Overview
This project is a high-security, professional deployment solution for a personal VPN on Microsoft Azure. It integrates **WireGuard** for high-performance tunneling, **AdGuard Home** for network-wide DNS ad-blocking, **OpenSpeedTest** for bandwidth testing, and **Glances** for server monitoring. The system is hardened at the OS and network layers and optimized for Azure's economic B-series VMs.

## Key Features
*   **Unified CLI Setup:** A single command (`setup.ps1`) manages the entire lifecycle.
*   **Performance Stack:** Automatic 2GB Swap, MTU 1420, and PersistentKeepalive 25.
*   **Monitoring Suite:** Integrated **OpenSpeedTest** and **Glances** dashboards.
*   **Security Lockdown:** Automated firewall management that opens ports for SSL validation and then locks them to the Admin's IP.
*   **User Management:** Dedicated CLI (`manage_users.ps1`) for adding/removing WireGuard peers via API.
*   **Auto-Maintenance:** Integrated **Watchtower** for automatic software updates.
*   **Hardened OS:** Includes Fail2Ban, kernel network hardening, and disabled password authentication.
*   **Full HTTPS:** Secure web access via Caddy and Let's Encrypt using `sslip.io` (Production SSL).

## Architecture
*   **Infrastructure:** Ubuntu 24.04 LTS on Azure, Static IP, Dynamic NSG.
*   **Networking:** Isolated Docker network with explicit host-port mapping for maximum compatibility.
*   **WireGuard Optimized:** Auto-detected Public IP Endpoint (Fixed `curl` expansion).

## Workflow
1.  Run `powershell ./setup.ps1`.
2.  Input Azure resources and optionally an **Initial WireGuard User** (e.g., "MyPhone").
3.  The system deploys, configures HTTPS, and locks down the firewall automatically.
4.  **Auto-Download:** If an initial user was requested, the `.conf` file is downloaded to your local folder.
5.  Use `powershell ./manage_users.ps1` to manage users day-to-day.
6.  Maintenance (SSL renewal) is handled via `automation/renew_ssl.ps1`.

## Recent Changes
*   **Feature:** Added `manage_users.ps1` for CLI-based WireGuard user management.
*   **Feature:** Setup now supports creating an initial user and auto-downloading the config.
*   **CI/CD:** Added GitHub Actions for automated linting and testing.
*   **Fixed:** WireGuard Endpoint configuration now correctly executes `curl` on the server side.
