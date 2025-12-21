# 🛡️ Ultimate Azure VPN & Server Suite

[![Azure](https://img.shields.io/badge/Azure-0078D4?style=for-the-badge&logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com/)
[![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=for-the-badge&logo=wireguard&logoColor=white)](https://www.wireguard.com/)
[![AdGuard](https://img.shields.io/badge/AdGuard-68BC71?style=for-the-badge&logo=adguard&logoColor=white)](https://adguard.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

A high-performance, security-hardened, and fully automated personal VPN solution deployed on Microsoft Azure. Featuring **WireGuard**, **AdGuard Home**, **OpenSpeedTest**, and **Glances**—all secured behind **Caddy** with automatic HTTPS.

---

## ✨ Key Features

*   **🚀 One-Click Setup:** A unified PowerShell CLI (`setup.ps1`) manages everything.
*   **🔒 Hardened by Design:** IP-Locked Management, Fail2Ban, Kernel Tweaks.
*   **⚡ Performance Optimized:** MTU Tuning, 2GB Swap, Persistent Keepalive.
*   **🌐 Complete Suite:**
    *   **VPN:** WireGuard (wg-easy)
    *   **DNS:** AdGuard Home (Hardened Privacy)
    *   **Speed:** OpenSpeedTest
    *   **Health:** Glances
*   **🔄 Zero Maintenance:** **Watchtower** automatically keeps everything updated.

---

## 🏗️ Architecture

```mermaid
graph TD
    User([Remote User]) -- VPN Tunnel: UDP 51820 --> VM[Azure Ubuntu VM]
    Admin([Admin]) -- HTTPS: 443 --> Caddy[Caddy Reverse Proxy]
    
    subgraph "Docker Stack"
        Caddy -- Proxy --> WG[WireGuard UI]
        Caddy -- Proxy --> AG[AdGuard Home]
        Caddy -- Proxy --> ST[OpenSpeedTest]
        Caddy -- Proxy --> GL[Glances]
        WG -- DNS Queries --> AG
    end
    
    subgraph "Security Layers"
        FW[Azure NSG - IP Locked]
        UFW[Ubuntu Firewall]
        F2B[Fail2Ban]
    end
```

---

## 🚀 Quick Start

### 1. Run the Installer
```powershell
powershell ./setup.ps1
```

### 2. Follow the CLI Prompts
*   Select your **Azure Region** and **Resource Names**.
*   Set your **Dashboard Passwords**.
*   Confirm with `y` to deploy.

### 3. Access Your Dashboards
Once the script finishes, your secure links will be ready:
*   **WireGuard UI:** `https://vpn.<SERVER_IP>.sslip.io`
*   **AdGuard Home:** `https://adguard.<SERVER_IP>.sslip.io`
*   **SpeedTest:** `https://speed.<SERVER_IP>.sslip.io`
*   **Glances:** `https://glances.<SERVER_IP>.sslip.io`

---

## 📜 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.