# Configuration Generator - Robust Enterprise Edition
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = $PSScriptRoot
. "$SCRIPT_DIR\lib.ps1"

# 1. Load Data
$config = Get-VpnConfig
$ag_user = $config.adguard.username

# 2. Handle Passwords
if ($MyInvocation.ExpectingInput) {
    $inputData = @($input | Where-Object { $_ -ne $null })
    $vpnPassword = if ($inputData[0]) { $inputData[0].Trim() } else { "password" }
    $agPassword = if ($inputData[1]) { $inputData[1].Trim() } else { "password" }
} else {
    $vpnPassword = (Read-Host "  VPN UI Password").Trim()
    $agPassword = (Read-Host "  Dashboard Password").Trim()
}
if (!$vpnPassword) { $vpnPassword = "password" }
if (!$agPassword) { $agPassword = "password" }

$vpnBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($vpnPassword))
$agBase64  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($agPassword))

# 3. Final Cloud-Init Template
$template = @'
#cloud-config
package_update: true
package_upgrade: false

write_files:
  - path: /etc/fail2ban/jail.local
    content: |
      [sshd]
      enabled = true
      port = 22
      maxretry = 3
      bantime = 1h

  - path: /root/setup.sh
    permissions: "0700"
    content: |
      #!/bin/bash
      set -e
      export DEBIAN_FRONTEND=noninteractive

      # 0. Fix Hostname and Wait for Net
      echo "127.0.0.1 $(hostname)" >> /etc/hosts
      sleep 15

      # 1. Install EVERYTHING (Reliable Method)
      apt-get update
      apt-get install -y docker.io docker-compose-v2 curl ufw apache2-utils fail2ban unattended-upgrades

      # 2. RAM Optimization
      if [ ! -f /swapfile ]; then
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
      fi

      # 3. Decode Passwords & Detect IP
      VPN_PASS=$(echo "{{VPN_B64}}" | base64 -d)
      AG_PASS=$(echo "{{AG_B64}}" | base64 -d)
      PUB_IP=$(curl -s https://api.ipify.org || echo "auto")

      # 4. Generate Hashes
      VPN_HASH=$(htpasswd -B -n -b admin "$VPN_PASS" | cut -d ":" -f 2)
      ESCAPED_VPN_HASH=$(echo "$VPN_HASH" | sed 's/\$/\$\$/g')
      AG_HASH=$(htpasswd -B -n -b admin "$AG_PASS" | cut -d ":" -f 2)

      # 5. Create AdGuard Config
      mkdir -p /root/adguard/conf
      cat <<EOF > /root/adguard/conf/AdGuardHome.yaml
      http:
        address: 0.0.0.0:8080
        session_ttl: 720h
      users:
        - name: "{{AG_USER}}"
          password: "$AG_HASH"
      dns:
        bind_hosts:
          - 0.0.0.0
        port: 53
        protection_enabled: true
        filtering_enabled: true
      schema_version: 14
      EOF

      # 6. Create Caddyfile
      cat <<'EOF' > /root/Caddyfile
      {
        email admin@sslip.io
      }
      adguard.DOMAIN_PLACEHOLDER {
        reverse_proxy 127.0.0.1:8080 {
          header_up Host {host}
          header_up X-Real-IP {remote_host}
        }
      }
      vpn.DOMAIN_PLACEHOLDER {
        reverse_proxy 127.0.0.1:51821
      }
      speed.DOMAIN_PLACEHOLDER {
        basicauth {
          {{AG_USER}} AG_HASH_PLACEHOLDER
        }
        reverse_proxy 127.0.0.1:3000
      }
      glances.DOMAIN_PLACEHOLDER {
        basicauth {
          {{AG_USER}} AG_HASH_PLACEHOLDER
        }
        reverse_proxy 127.0.0.1:61208
      }
      EOF
      
      sed -i "s|AG_HASH_PLACEHOLDER|$AG_HASH|g" /root/Caddyfile

      # 7. Create Docker Compose (Everything in Host Mode)
      cat <<EOF > /root/docker-compose.yml
      services:
        caddy:
          image: caddy:latest
          container_name: caddy
          restart: unless-stopped
          network_mode: host
          volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "./caddy_data:/data"]
        wg-easy:
          image: ghcr.io/wg-easy/wg-easy
          container_name: wg-easy
          restart: unless-stopped
          network_mode: host
          environment:
            - WG_HOST=$PUB_IP
            - PASSWORD_HASH=$ESCAPED_VPN_HASH
            - WG_DEFAULT_DNS=10.8.0.1
            - WG_MTU=1420
            - WG_PERSISTENT_KEEPALIVE=25
          volumes: ["./wg-easy:/etc/wireguard"]
          cap_add: [NET_ADMIN, SYS_MODULE]
        adguardhome:
          image: adguard/adguardhome
          container_name: adguardhome
          restart: unless-stopped
          network_mode: host
          volumes: ["./adguard/work:/opt/adguardhome/work", "./adguard/conf:/opt/adguardhome/conf"]
        speedtest:
          image: openspeedtest/latest
          container_name: speedtest
          restart: unless-stopped
          network_mode: host
        glances:
          image: nicolargo/glances:latest
          container_name: glances
          restart: unless-stopped
          network_mode: host
          pid: host
          environment: [GLANCES_OPT=-w]
          volumes: ["/var/run/docker.sock:/var/run/docker.sock:ro"]
        watchtower:
          image: containrrr/watchtower
          volumes: ["/var/run/docker.sock:/var/run/docker.sock"]
          command: --cleanup --interval 86400
          restart: unless-stopped
      EOF

      # 8. Routing & NAT
      sysctl -w net.ipv4.ip_forward=1
      echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
      iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      iptables -A FORWARD -i wg0 -j ACCEPT
      iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

      # 9. DNS Fix
      systemctl stop systemd-resolved || true
      systemctl disable systemd-resolved || true
      rm -f /etc/resolv.conf
      echo "nameserver 1.1.1.1" > /etc/resolv.conf

      # 10. Firewall
      ufw default deny incoming
      ufw allow ssh; ufw allow 80/tcp; ufw allow 443/tcp; ufw allow 51820/udp; ufw allow 53/udp; ufw allow 53/tcp
      ufw allow in on wg0
      echo "y" | ufw enable
      
      # 11. Launch
      cd /root && docker compose up -d
runcmd:
  - bash /root/setup.sh
'@

# 4. Inject & Write
$final = $template.Replace("{{VPN_B64}}", $vpnBase64).Replace("{{AG_B64}}", $agBase64).Replace("{{AG_USER}}", $ag_user)
$outputPath = Join-Path $SCRIPT_DIR "..\final_cloud_init.yaml"
[System.IO.File]::WriteAllText($outputPath, $final, [System.Text.Encoding]::ASCII)
Show-Success "Corrected configuration generated."
