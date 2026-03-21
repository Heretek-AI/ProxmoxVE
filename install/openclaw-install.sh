#!/usr/bin/env bash

# Author: BIllyOutlast
# License: MIT | https://github.com/Heretek-AI/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/openclaw/openclaw
# Documentation: https://docs.openclaw.ai

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  ca-certificates \
  build-essential \
  python3 \
  python3-pip \
  python3-venv \
  git \
  procps \
  debian-keyring \
  debian-archive-keyring \
  ffmpeg \
  sudo
msg_ok "Installed Dependencies"

# Install Caddy for HTTPS reverse proxy
msg_info "Installing Caddy (HTTPS Reverse Proxy)"
$STD apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' >/etc/apt/sources.list.d/caddy-stable.list
$STD apt-get update
$STD apt-get install -y caddy
msg_ok "Installed Caddy"

# Setup Node.js 24 (recommended by OpenClaw documentation)
NODE_VERSION="24" setup_nodejs

# Install uv (Python package manager) - OpenClaw uses Python for some tools
PYTHON_VERSION="3.12" setup_uv

# Create unprivileged user for OpenClaw (with nologin shell for security)
msg_info "Creating OpenClaw User"
if ! id -u openclaw &>/dev/null; then
  # Create user with nologin shell to prevent direct login
  useradd -r -s /usr/sbin/nologin -d /home/openclaw -m openclaw
fi
msg_ok "Created OpenClaw User"

# Configure restricted sudo for openclaw user (only specific commands needed)
msg_info "Configuring Restricted Sudo for OpenClaw User"
cat <<EOF >/etc/sudoers.d/openclaw
# OpenClaw needs specific permissions for package management and service control
# SECURITY: Restricted to only the commands needed by the application
openclaw ALL=(ALL) NOPASSWD: /usr/bin/npm, /usr/bin/node, /home/linuxbrew/.linuxbrew/bin/brew
openclaw ALL=(ALL) NOPASSWD: /usr/bin/systemctl --user *
EOF
chmod 440 /etc/sudoers.d/openclaw
msg_ok "Configured Restricted Sudo"

# Configure npm to use user-writable directory for global packages
msg_info "Configuring npm for User Packages"
mkdir -p /home/openclaw/.npm-global
chown -R openclaw:openclaw /home/openclaw/.npm-global
# Set npm prefix for openclaw user to use home directory
# Using sudo -u since openclaw user has nologin shell
# IMPORTANT: Run from openclaw's home directory to avoid permission errors
cd /home/openclaw && sudo -u openclaw npm config set prefix /home/openclaw/.npm-global
# Add to PATH for openclaw user
echo 'export PATH=/home/openclaw/.npm-global/bin:$PATH' >> /home/openclaw/.bashrc
msg_ok "Configured npm for User Packages"

# Install Homebrew for the openclaw user
msg_info "Installing Homebrew"
# Create Homebrew directory structure
mkdir -p /home/linuxbrew/.linuxbrew
chown -R openclaw:openclaw /home/linuxbrew 2>/dev/null || true

# Download Homebrew installer
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o /tmp/brew-install.sh

# Run installer non-interactively as openclaw user
# CI=1 and NONINTERACTIVE=1 enable fully automated installation
# Pipe empty string to automatically confirm the "Press RETURN" prompt
# Using sudo -u since openclaw user has nologin shell
# IMPORTANT: Run from openclaw's home directory to avoid permission errors
# Output redirected to suppress verbose installation messages
cd /home/openclaw && echo "" | CI=1 NONINTERACTIVE=1 sudo -u openclaw bash /tmp/brew-install.sh >/dev/null 2>&1 || true
rm -f /tmp/brew-install.sh

# Add Homebrew to PATH for openclaw user
if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  # Add to .bashrc for interactive shells
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> /home/openclaw/.bashrc
  # Add to .profile for login shells
  echo '' >> /home/openclaw/.profile
  echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> /home/openclaw/.profile
  msg_ok "Installed Homebrew"
  
  # Install GCC (recommended by Homebrew)
  msg_info "Installing GCC via Homebrew"
  /home/linuxbrew/.linuxbrew/bin/brew install gcc 2>/dev/null || true
  msg_ok "Installed GCC"
else
  msg_warn "Homebrew installation may have failed - check logs"
fi

msg_info "Installing OpenClaw"
# Install OpenClaw globally as the openclaw user
# Using sudo -u since openclaw user has nologin shell
# IMPORTANT: Run from openclaw's home directory to avoid permission errors
cd /home/openclaw && sudo -u openclaw npm install -g openclaw@latest
msg_ok "Installed OpenClaw"

msg_info "Creating Directories"
mkdir -p /opt/openclaw
mkdir -p /home/openclaw/.openclaw
mkdir -p /home/openclaw/.openclaw/workspace
mkdir -p /home/openclaw/.openclaw/workspace/memory
chown -R openclaw:openclaw /opt/openclaw
chown -R openclaw:openclaw /home/openclaw/.openclaw
# Security: Restrict state directory to owner only (fixes world-readable warning)
chmod 700 /home/openclaw/.openclaw
msg_ok "Created Directories"

msg_info "Creating OpenClaw Configuration"
# Get the container's IP address for allowedOrigins
CONTAINER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
# Get hostname for HTTPS origins
HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
# Generate a secure random auth token (32 bytes = 64 hex chars)
AUTH_TOKEN=$(openssl rand -hex 32)
cat <<EOF >/home/openclaw/.openclaw/openclaw.json
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "${AUTH_TOKEN}"
    },
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:18789",
        "http://127.0.0.1:18789",
        "https://localhost:18790",
        "https://127.0.0.1:18790",
        "https://${CONTAINER_IP}:18790",
        "https://${HOSTNAME_FQDN}:18790"
      ]
    },
    "reload": {
      "mode": "hybrid"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/home/openclaw/.openclaw/workspace"
    }
  }
}
EOF
chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
# Security: Restrict config file to owner only (fixes world-readable critical issue)
chmod 600 /home/openclaw/.openclaw/openclaw.json
msg_ok "Created OpenClaw Configuration"

msg_info "Creating Self-Signed Certificate for HTTPS"
# Generate self-signed certificate with IP in SAN (Caddy's tls internal doesn't work with IPs)
mkdir -p /etc/caddy/certs
CONTAINER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)

# Generate self-signed certificate valid for 365 days
openssl req -x509 -newkey rsa:4096 -keyout /etc/caddy/certs/openclaw.key \
  -out /etc/caddy/certs/openclaw.crt \
  -days 365 -nodes \
  -subj "/CN=openclaw-local" \
  -addext "subjectAltName=IP:127.0.0.1,IP:${CONTAINER_IP},DNS:localhost,DNS:${HOSTNAME_FQDN}" 2>/dev/null

# Set proper permissions
chmod 644 /etc/caddy/certs/openclaw.crt
chmod 600 /etc/caddy/certs/openclaw.key
chown caddy:caddy /etc/caddy/certs/openclaw.crt /etc/caddy/certs/openclaw.key
msg_ok "Created Self-Signed Certificate"

msg_info "Creating Caddy HTTPS Reverse Proxy"
# Create Caddyfile for HTTPS reverse proxy with explicit certificate paths
cat <<EOF >/etc/caddy/Caddyfile
# OpenClaw HTTPS Reverse Proxy
# Access via https://<container-ip>:18790

:18790 {
    tls /etc/caddy/certs/openclaw.crt /etc/caddy/certs/openclaw.key
    
    # Caddy automatically handles WebSocket upgrades
    reverse_proxy localhost:18789 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
    }
    
    # Log requests
    log {
        output file /var/log/caddy/openclaw.log
        format console
    }
}
EOF

# Create log directory
mkdir -p /var/log/caddy
chown caddy:caddy /var/log/caddy

# Enable Caddy
systemctl enable -q caddy
msg_ok "Created Caddy HTTPS Reverse Proxy"

# ═══════════════════════════════════════════════════════════════════════════════
# Systemd Service Setup for LXC Containers
# ═══════════════════════════════════════════════════════════════════════════════
# LXC containers have limited systemd user session support due to D-Bus limitations.
# We use system-level services with User=openclaw directive instead of user services.
# ═══════════════════════════════════════════════════════════════════════════════

msg_info "Creating System-Level Systemd Service (LXC Mode)"

# Create compile cache directory for Node.js optimization
mkdir -p /var/tmp/openclaw-compile-cache
chown openclaw:openclaw /var/tmp/openclaw-compile-cache

# Create secure temp directory for OpenClaw (required for security checks)
# OpenClaw requires a temp dir that is only accessible by the openclaw user
mkdir -p /var/tmp/openclaw
chown openclaw:openclaw /var/tmp/openclaw
chmod 700 /var/tmp/openclaw

# Create system-level service file
cat <<EOF >/etc/systemd/system/openclaw-gateway.service
[Unit]
Description=OpenClaw Gateway
Documentation=https://docs.openclaw.ai
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw/.openclaw
Environment="PATH=/home/openclaw/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
Environment="OPENCLAW_CONFIG_PATH=/home/openclaw/.openclaw/openclaw.json"
Environment="NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache"
Environment="TMPDIR=/var/tmp/openclaw"
Environment="OPENCLAW_NO_RESPAWN=1"
# LXC container mode - skip systemd service management (D-Bus not available)
Environment="OPENCLAW_SKIP_SERVICE_INSTALL=1"
ExecStart=/home/openclaw/.npm-global/bin/openclaw gateway
Restart=on-failure
RestartSec=10

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/openclaw/.openclaw /var/tmp/openclaw-compile-cache /var/tmp/openclaw

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon
systemctl daemon-reload

# Enable the service
systemctl enable -q openclaw-gateway

msg_ok "Created System-Level Service"

msg_info "Starting Caddy HTTPS Proxy"
# Restart Caddy to apply configuration
systemctl restart caddy
msg_ok "Started Caddy HTTPS Proxy"

msg_info "Starting OpenClaw Gateway"
systemctl start openclaw-gateway

# Wait for gateway to be ready
sleep 5

# Check if gateway is running
if systemctl is-active --quiet openclaw-gateway; then
  msg_ok "Gateway Service Started Successfully"
else
  msg_error "Gateway Service Failed to Start"
  msg_info "Checking service status..."
  systemctl status openclaw-gateway --no-pager || true
  msg_info "View logs with: journalctl -u openclaw-gateway -f"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Final Verification
# ═══════════════════════════════════════════════════════════════════════════════

msg_info "Verifying Installation"

# Check if gateway port is listening
sleep 3
if command -v ss &>/dev/null; then
  if ss -tln | grep -q ":18789"; then
    msg_ok "Gateway Port 18789 is Listening"
  else
    msg_warn "Gateway Port 18789 Not Yet Listening - Service May Still Be Starting"
  fi
fi

# Check if Caddy is running and proxy is configured
if systemctl is-active --quiet caddy; then
  msg_ok "Caddy HTTPS Proxy is Running"
else
  msg_warn "Caddy Service Not Running - HTTPS Access Unavailable"
fi

# Store auth token securely (not displayed in console for security)
cat <<EOF >/home/openclaw/.openclaw/auth_token
${AUTH_TOKEN}
EOF
chmod 600 /home/openclaw/.openclaw/auth_token
chown openclaw:openclaw /home/openclaw/.openclaw/auth_token

# ═══════════════════════════════════════════════════════════════════════════════
# Display Post-Installation Information
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  OpenClaw Installation Complete"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Auth Token saved to: /home/openclaw/.openclaw/auth_token"
echo "  View with: cat /home/openclaw/.openclaw/auth_token"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Access URLs"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  HTTP:  http://${CONTAINER_IP}:18789"
echo "  HTTPS: https://${CONTAINER_IP}:18790"
echo ""
echo "  Note: HTTPS uses a self-signed certificate. Click 'Advanced' -> 'Proceed to site'"
echo "        in your browser to accept the certificate."
echo ""
echo "═══════════════════════════════════════��═══════════════════════════════════════"
echo "  LXC Container Service Management"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  System-level service installed (required for LXC containers)."
echo ""
echo "  Service Management Commands:"
echo "    Status:  systemctl status openclaw-gateway"
echo "    Start:   systemctl start openclaw-gateway"
echo "    Stop:    systemctl stop openclaw-gateway"
echo "    Restart: systemctl restart openclaw-gateway"
echo "    Logs:    journalctl -u openclaw-gateway -f"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Running OpenClaw Commands"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  The openclaw user has no login shell for security."
echo "  Use the full path to run openclaw commands:"
echo ""
echo "    /home/openclaw/.npm-global/bin/openclaw --help"
echo "    /home/openclaw/.npm-global/bin/openclaw doctor"
echo "    /home/openclaw/.npm-global/bin/openclaw gateway status"
echo ""
echo "  Or set PATH temporarily in your shell:"
echo "    export PATH=/home/openclaw/.npm-global/bin:\$PATH"
echo "    openclaw --help"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Next Steps"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  1. Configure a Model Provider (REQUIRED for OpenClaw to function):"
echo ""
echo "     Option A - Ollama (Local, Free):"
echo "       • Install Ollama: curl -fsSL https://ollama.com/install.sh | sh"
echo "       • Pull a model: ollama pull llama3.2"
echo "       • Pull embedding model: ollama pull nomic-embed-text"
echo "       • Configure OpenClaw:"
echo "         /home/openclaw/.npm-global/bin/openclaw configure"
echo "         # Select Ollama as provider"
echo ""
echo "     Option B - OpenAI API:"
echo "       /home/openclaw/.npm-global/bin/openclaw models auth add --provider openai"
echo "       # Enter your API key when prompted"
echo ""
echo "     Option C - Anthropic Claude:"
echo "       /home/openclaw/.npm-global/bin/openclaw models auth add --provider anthropic"
echo "       # Enter your API key when prompted"
echo ""
echo "  2. Configure Channels (Optional - for messaging):"
echo "     /home/openclaw/.npm-global/bin/openclaw channels add --channel telegram --token YOUR_BOT_TOKEN"
echo "     /home/openclaw/.npm-global/bin/openclaw channels add --channel discord --token YOUR_BOT_TOKEN"
echo ""
echo "  3. Verify Installation:"
echo "     /home/openclaw/.npm-global/bin/openclaw doctor"
echo "     /home/openclaw/.npm-global/bin/openclaw gateway status"
echo "     /home/openclaw/.npm-global/bin/openclaw models status"
echo ""
echo "  4. View Logs:"
echo "     journalctl -u openclaw-gateway -f"
echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "  Memory Search Configuration"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Memory search requires an embedding provider. Configure one of:"
echo "  - Ollama (local): https://docs.openclaw.ai/reference/memory-config"
echo "  - OpenAI, Gemini, Voyage, or Mistral (cloud)"
echo ""
echo "  To configure Ollama (recommended for offline use):"
echo "    1. Ensure Ollama is running on this host or accessible remotely"
echo "    2. Pull an embedding model: ollama pull nomic-embed-text"
echo "    3. Edit config: nano /home/openclaw/.openclaw/openclaw.json"
echo ""
echo "  Add to config under 'agents.defaults.memorySearch':"
echo '    { "provider": "ollama", "model": "nomic-embed-text",'
echo '      "remote": { "baseUrl": "http://YOUR_OLLAMA_HOST:11434" } }'
echo ""

motd_ssh
customize
cleanup_lxc
