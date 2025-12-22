# HTTPS Configuration Script - Python-Powered Robust Injector
param ([string]$ServerIp)
$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
. "$ScriptDir\lib.ps1"

if (!$ServerIp) { $config = Get-VpnConfig; $ServerIp = $config.server.ip }
if (!$ServerIp) { Show-Error "No Server IP provided."; exit 1 }

Show-Header "CONFIGURING HTTPS & DNS REWRITES"
Show-Step "Target: $ServerIp"

$domain = "$ServerIp.sslip.io"

# Create a local Python helper script (Standard string to avoid Here-String issues)
$pythonCode = "import os, re`n" +
"domain = '$domain'`n" +
"caddyfile = '/root/Caddyfile'`n" +
"ag_config = '/root/adguard/conf/AdGuardHome.yaml'`n" +
"def replace_placeholder(filepath, domain):`n" +
"    if os.path.exists(filepath):`n" +
"        with open(filepath, 'r') as f: content = f.read()`n" +
"        new_content = re.sub(r'DOMAIN_PLACEHOLDER', domain, content, flags=re.IGNORECASE)`n" +
"        with open(filepath, 'w') as f: f.write(new_content)`n" +
"        print(f'[OK] {filepath} updated.')`n" +
"replace_placeholder(caddyfile, domain)`n" +
"replace_placeholder(ag_config, domain)`n" +
"os.system('sudo docker compose -f /root/docker-compose.yml restart caddy adguardhome')"

$tempFile = Join-Path $env:TEMP "configure_https.py"
Set-Content -Path $tempFile -Value $pythonCode -Encoding UTF8

Show-Step "Syncing configuration via Python..."
try {
    scp -o StrictHostKeyChecking=no $tempFile azureuser@${ServerIp}:/tmp/configure_https.py
    ssh -o StrictHostKeyChecking=no azureuser@${ServerIp} "sudo python3 /tmp/configure_https.py"
    
    if ($LASTEXITCODE -eq 0) {
        Show-Success "HTTPS and DNS Rewrites enabled."
    } else {
        Show-Error "Configuration failed."
    }
} catch {
    Show-Error "Connection failed: $_"
}
Remove-Item $tempFile -ErrorAction SilentlyContinue
