# Project Context: Azure WireGuard & AdGuard Home VPN (Automated)

## Project Overview
This project provides a fully automated solution for deploying a secure, ad-blocking VPN server on Microsoft Azure. It utilizes **WireGuard** for the VPN tunnel and **AdGuard Home** for DNS-based ad blocking. The stack is containerized with Docker and served securely via **Caddy** (Reverse Proxy) with automatic HTTPS using `sslip.io` and Let's Encrypt.

## Key Features
*   **Fully Automated:** PowerShell scripts handle config generation, Azure deployment, and post-install setup.
*   **Secure by Default:** Management ports (SSH, HTTP, HTTPS) are automatically locked to the deployer's Public IP. VPN port remains global.
*   **HTTPS Enabled:** Automatic SSL certificates for AdGuard and WireGuard Web UIs using Magic DNS.
*   **Cost Effective:** Designed for Azure B-series VMs (Ubuntu 24.04).

## Architecture

### Infrastructure
*   **Platform:** Microsoft Azure
*   **Resource:** Virtual Machine (Ubuntu 24.04 LTS)
*   **Networking:** Static Public IP. NSG rules dynamically restricted to admin IP.

### Software Stack (Dockerized)
1.  **WireGuard (`wg-easy`)**:
    *   **Function:** VPN Server & Web UI.
    *   **Ports:** UDP `51820` (VPN Tunnel - Public), TCP `51821` (Web UI - Internal).
2.  **AdGuard Home**:
    *   **Function:** DNS Server & Ad Blocker.
    *   **Ports:** TCP `8080` (Admin Panel - Internal), TCP/UDP `53` (DNS - Internal).
3.  **Caddy**:
    *   **Function:** Reverse Proxy & SSL Termination.
    *   **Ports:** TCP `80`, `443` (Public - Restricted to Admin IP).
    *   **Role:** Proxies traffic to WireGuard (`/`) and AdGuard (`/`) based on subdomains.

## Key Files & Scripts (`automation/`)

*   **`azure_deploy.ps1`**: Main deployment script. Creates Resource Group, VM, and NSG rules locked to Admin IP.
*   **`generate_cloud_init.ps1`**: Generates `final_cloud_init.yaml` from `config.yaml` and templates. Handles password hashing and Caddyfile creation.
*   **`configure_https.ps1`**: Post-deployment script. Configures Caddy with the dynamic IP-based domain (`<IP>.sslip.io`) and restarts services.
*   **`verify_deployment.ps1`**: Verifies SSH connectivity and Docker container status.
*   **`azure_destroy.ps1`**: Deletes the entire environment.
*   **`config.yaml`**: Central configuration file for credentials and settings.

## Workflow
1.  **Generate Config:** `powershell automation/generate_cloud_init.ps1`
2.  **Deploy to Azure:** `powershell automation/azure_deploy.ps1`
3.  **Enable HTTPS:** `powershell automation/configure_https.ps1`
4.  **Connect:** Access Web UIs via provided HTTPS links.

## Conventions
*   **PowerShell First:** All automation logic is in `.ps1` files.
*   **Infrastructure as Code:** Server config is defined in `cloud-init.yaml` (generated).
*   **Security:** SSH keys enforced. Admin access restricted by IP. HTTPS forced.