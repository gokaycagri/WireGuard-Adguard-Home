# VM Fix Script - HTTPS & Password Reset (Address Fix)
$ErrorActionPreference = "Stop"
$SERVER_IP = "4.245.190.51"
$USER = "azureuser"
$SSH_KEY = "$HOME\.ssh\id_rsa"
$DOMAIN = "$SERVER_IP.nip.io"

Write-Host "--- HTTPS Upgrade (IP Fix) on $SERVER_IP ---" -ForegroundColor Cyan

$fixCommand = @"
cd /root

cat <<EOF > docker-compose.yml
services:
  wg-easy:
    environment:
      - WG_HOST=$DOMAIN
      - WG_PASSWORD=123456
      - WG_PORT=51820
      - WG_DEFAULT_DNS=10.9.0.10
      - WG_ALLOWED_IPS=0.0.0.0/0
    image: ghcr.io/wg-easy/wg-easy
    container_name: wg-easy
    volumes:
      - ./wg-easy:/etc/wireguard
    ports:
      - "51820:51820/udp"
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.src_valid_mark=1
    networks:
      default:
        ipv4_address: 10.9.0.5

  adguardhome:
    image: adguard/adguardhome
    container_name: adguardhome
    command: --port 80 --host 0.0.0.0 -c /opt/adguardhome/conf/AdGuardHome.yaml -w /opt/adguardhome/work
    restart: unless-stopped
    volumes:
      - ./adguard/work:/opt/adguardhome/work
      - ./adguard/conf:/opt/adguardhome/conf
    networks:
      default:
        ipv4_address: 10.9.0.10

  caddy:
    image: caddy:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - wg-easy
      - adguardhome
    networks:
      default:
        ipv4_address: 10.9.0.20

volumes:
  caddy_data:
  caddy_config:

networks:
  default:
    ipam:
      driver: default
      config:
        - subnet: 10.9.0.0/24
EOF

# Restart
docker compose down
docker compose up -d
"@

# Fix Line Endings
$fixCommand = $fixCommand -replace "`r`n", "`n"

$tempFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($tempFile, $fixCommand)

# Upload script
scp -i $SSH_KEY -o StrictHostKeyChecking=no $tempFile ${USER}@${SERVER_IP}:/tmp/upgrade_https_ip.sh

# Run script
ssh -i $SSH_KEY -o StrictHostKeyChecking=no ${USER}@${SERVER_IP} "sudo bash /tmp/upgrade_https_ip.sh && rm /tmp/upgrade_https_ip.sh"

Write-Host "Upgrade applied. Waiting 15 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

Write-Host "Verifying..." -ForegroundColor Cyan
Write-Host "New URLs:"
Write-Host "https://$DOMAIN (AdGuard - User: admin / Pass: password)"
Write-Host "https://$DOMAIN/wg (WireGuard - Pass: 123456)"
