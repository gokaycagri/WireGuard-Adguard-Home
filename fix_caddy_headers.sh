#!/bin/bash
# Fix Caddy Headers for AdGuard & SpeedTest
# Get Hash for Basic Auth if needed (using 'Cagri123' or existing)
# We assume BasicAuth is already set or we can disable it for testing if needed. 
# For now, I'll keep the structure but ensure headers are correct.

cat <<'EOF' > /root/Caddyfile
{
  email admin@sslip.io
}

adguard.4.231.217.133.sslip.io {
  reverse_proxy 172.20.0.53:8080 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}

vpn.4.231.217.133.sslip.io {
  reverse_proxy wg-easy:51821
}

speed.4.231.217.133.sslip.io {
  # SpeedTest needs WebSocket support
  reverse_proxy speedtest:3000 {
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    header_up X-Forwarded-For {remote_host}
    header_up X-Forwarded-Proto {scheme}
  }
}

glances.4.231.217.133.sslip.io {
  reverse_proxy glances:61208
}
EOF

cd /root && sudo docker compose restart caddy
echo "Caddy updated for WebSockets and AdGuard headers."
