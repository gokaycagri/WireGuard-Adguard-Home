# Project Context: Azure WireGuard & AdGuard Home VPN (Pro Edition)

## Project Overview
This project is a high-security, fully automated deployment solution for a personal VPN on Microsoft Azure. It combines **WireGuard** for tunneling and **AdGuard Home** for DNS-blocking. The system is hardened at the kernel and network levels and is managed through a unified PowerShell CLI.

## Key Features
*   **Interactive CLI Setup:** A single script (`setup.ps1`) manages the entire lifecycle, from configuration to deployment.
*   **Advanced Hardening:** Includes Fail2Ban, Kernel network hardening, and restricted SSH access (no passwords).
*   **Geo-Blocking:** Integrated firewall rules that restrict access to your server from a specific country only.
*   **Automatic Updates:** Managed by **Watchtower**, ensuring all containers are kept up-to-date daily.
*   **Automatic HTTPS:** Managed by **Caddy** with SSL certificates via Let's Encrypt and `sslip.io`.
*   **No Local Dependencies:** Password hashing is handled securely on the server; no Python or Node.js required on your local machine.

## Architecture
*   **Infrastructure:** Azure VM (Ubuntu 24.04), Static Public IP, NSG locked to Admin IP.
*   **Networking:** Isolated Docker bridge network (`172.20.0.0/24`) with internal routing.
*   **Security:** Management ports (22, 80, 443) are restricted to the deployer's IP address.

## Core Scripts (`automation/`)
*   **`setup.ps1` (Root):** The entry point. Interactive configuration and deployment orchestrator.
*   **`azure_deploy.ps1`:** Creates Azure resources and updates `config.yaml` with the final IP.
*   **`generate_cloud_init.ps1`:** Generates the server boot script with hardened logic and dynamic credentials.
*   **`configure_https.ps1`:** Finalizes Caddy settings after the server obtains its IP.
*   **`check_requirements.ps1`:** Verifies Azure CLI and SSH keys.
*   **`azure_destroy.ps1`:** Completely removes the Azure resource group.

## Workflow
1.  Run `powershell ./setup.ps1`.
2.  Input your desired Azure settings and passwords.
3.  Choose "y" to deploy.
4.  Wait for the automated HTTPS configuration to finish.
5.  Connect via the generated `sslip.io` links.
