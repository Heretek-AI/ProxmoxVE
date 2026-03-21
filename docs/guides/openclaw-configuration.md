# OpenClaw Configuration Guide

## "Device Identity Required" Error Fix

If you see this error when accessing the Control UI from another machine:

```
control ui requires device identity (use HTTPS or localhost secure context)
```

**This is a browser security requirement.** The Web Crypto API (used for device identity) only works in secure contexts - either HTTPS or localhost.

### Solution 1: SSH Tunnel (Recommended for LAN)

Access OpenClaw via localhost through an SSH tunnel:

```bash
# On your local machine, create an SSH tunnel
ssh -L 18789:localhost:18789 root@<container-ip>

# Then access in your browser
http://localhost:18789
```

### Solution 2: Allow Insecure Auth (LAN Only)

**Warning:** This reduces security. Only use on trusted networks.

Add `allowInsecureAuth: true` to your OpenClaw configuration:

```bash
# Edit configuration
nano ~/.openclaw/openclaw.json
```

```json
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "controlUi": {
      "allowedOrigins": ["http://localhost:18789", "http://127.0.0.1:18789", "http://192.168.31.39:18789"],
      "allowInsecureAuth": true
    },
    "auth": {
      "mode": "token",
      "token": "your-secure-token-here"
    }
  }
}
```

Then restart:

```bash
su - openclaw -c "systemctl --user restart openclaw-gateway"
```

**Important:**

- `allowInsecureAuth` only works for localhost connections in non-secure HTTP contexts
- It does **NOT** bypass device identity for remote (non-localhost) connections
- You must still use SSH tunnel or HTTPS for remote LAN access

### Solution 3: HTTPS Reverse Proxy (Production)

Set up Caddy or Nginx with SSL certificates for secure HTTPS access.

### Solution 4: Tailscale VPN

Install Tailscale on both machines and access via Tailscale IP.

### Emergency Break-Glass (NOT Recommended)

For emergency access only, you can completely disable device auth:

```json
{
  "gateway": {
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
```

**⚠️ WARNING:** This is a severe security downgrade. Revert immediately after emergency use.

## "Origin Not Allowed" Error Fix

If you see this error when accessing the Control UI from another machine:

```
origin not allowed (open the Control UI from the gateway host or allow it in gateway.controlUi.allowedOrigins)
```

**Quick Fix:**

```bash
# Get your container IP
CONTAINER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

# Create configuration with allowed origins
mkdir -p ~/.openclaw
cat > ~/.openclaw/openclaw.json << EOF
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:18789",
        "http://127.0.0.1:18789",
        "http://${CONTAINER_IP}:18789"
      ]
    }
  }
}
EOF

# Apply and restart
su - openclaw -c "systemctl --user restart openclaw-gateway"
```

**Note:** Even with `allowedOrigins` configured, you still need a secure context (HTTPS or localhost) for the device identity requirement. Use SSH tunneling for LAN access.

## Network Binding Configuration

By default, OpenClaw binds to localhost (127.0.0.1) only. To make it accessible from other machines on your network, you need to:

1. **Bind to all interfaces** (`--bind lan`)
2. **Configure allowed origins** (required for non-loopback bindings)

### Bind Options

| Option     | Description                       | Use Case             |
| ---------- | --------------------------------- | -------------------- |
| `loopback` | Binds to 127.0.0.1 only           | Default, most secure |
| `lan`      | Binds to 0.0.0.0 (all interfaces) | Local network access |
| `tailnet`  | Binds to Tailscale interface      | VPN access only      |
| `auto`     | Automatic selection               | Let OpenClaw decide  |

### Method 1: Configure Command (Recommended for Existing Installations)

```bash
# Open the gateway configuration
openclaw configure --section gateway

# Set bind to "lan" when prompted
# Then restart the service
su - openclaw -c "systemctl --user restart openclaw-gateway"
```

### Method 2: Manual Configuration

Edit the configuration file:

```bash
# Edit as the openclaw user
su - openclaw
nano ~/.openclaw/openclaw.json
```

Add the configuration with your IP:

```json
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "controlUi": {
      "allowedOrigins": ["http://localhost:18789", "http://127.0.0.1:18789", "http://192.168.1.4:18789"]
    }
  }
}
```

Apply changes:

```bash
systemctl --user restart openclaw-gateway
```

### Method 3: Quick Fix for Existing Installations

For existing installations, run these commands:

```bash
# Get your container IP
CONTAINER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

# Create configuration with allowed origins (as openclaw user)
su - openclaw -c "mkdir -p ~/.openclaw"
su - openclaw -c "cat > ~/.openclaw/openclaw.json << EOF
{
  \"gateway\": {
    \"bind\": \"lan\",
    \"port\": 18789,
    \"controlUi\": {
      \"allowedOrigins\": [
        \"http://localhost:18789\",
        \"http://127.0.0.1:18789\",
        \"http://${CONTAINER_IP}:18789\"
      ]
    }
  }
}
EOF"

# Restart the service
su - openclaw -c "systemctl --user restart openclaw-gateway"
```

### Method 4: Environment Variable

You can also set the bind mode via environment variable:

```bash
# Add to /etc/environment or the systemd service file
OPENCLAW_BIND=lan
```

## Verification

Check the current binding:

```bash
openclaw gateway status
```

Output should show:

```
bind: lan
listener: 0.0.0.0:18789
```

## Security Considerations

When binding to all interfaces (`lan`):

1. **Token Authentication**: OpenClaw uses token-based authentication. The token is generated on first run and displayed in the startup output.

2. **Firewall**: Consider adding firewall rules to restrict access:

   ```bash
   # Allow only specific IP ranges
   ufw allow from 192.168.31.0/24 to any port 18789
   ```

3. **Reverse Proxy**: For production use, consider placing OpenClaw behind a reverse proxy (nginx, Caddy) with SSL:

   ```nginx
   server {
       listen 443 ssl;
       server_name openclaw.yourdomain.com;

       location / {
           proxy_pass http://127.0.0.1:18789;
           proxy_http_version 1.1;
           proxy_set_header Upgrade $http_upgrade;
           proxy_set_header Connection "upgrade";
       }
   }
   ```

4. **Never expose directly to the internet**: The gateway provides administrative access to your system. Always use VPN, reverse proxy with authentication, or Tailscale for remote access.

## Remote Access Options

### SSH Tunnel (Most Secure for Temporary Access)

```bash
# On your local machine
ssh -N -L 18789:127.0.0.1:18789 root@<server-ip>

# Then access in browser
http://localhost:18789
```

### Tailscale (Recommended for Permanent Remote Access)

1. Install Tailscale on both machines
2. Set OpenClaw bind to `tailnet`:

   ```bash
   openclaw configure --section gateway
   # Set bind to "tailnet"
   su - openclaw -c "systemctl --user restart openclaw-gateway"
   ```

3. Access via Tailscale IP: `http://<tailscale-ip>:18789`

## Troubleshooting

### Gateway Not Starting

```bash
# Check logs (as openclaw user)
su - openclaw -c "journalctl --user -u openclaw-gateway -f"

# Or from root
journalctl --user -u openclaw-gateway -f --user-unit

# Common issues:
# - Port already in use: lsof -i :18789
# - Permission denied: ensure running as correct user
```

### Cannot Connect from Remote

1. Verify binding: `openclaw gateway status` should show `0.0.0.0:18789`
2. Check firewall: `ufw status` or `iptables -L -n`
3. Verify network connectivity: `ping <server-ip>`

### Token Authentication Issues

```bash
# Regenerate token
openclaw doctor --generate-gateway-token

# View current token
openclaw gateway status
```

## Installing Homebrew (Optional)

If you need to install additional tools via Homebrew, follow these steps:

### Prerequisites

The `openclaw` user needs sudo access and a password set. By default, the user is created without a password.

### Step 1: Set Password for openclaw User

As root, set a password for the openclaw user:

```bash
passwd openclaw
# Enter and confirm the new password
```

### Step 2: Install Homebrew

Switch to the openclaw user and run the installer:

```bash
su - openclaw
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

When prompted:

1. Enter the openclaw password for sudo access
2. Press ENTER to continue when the installer shows the directories it will create

### Step 3: Add Homebrew to PATH

After installation, add Homebrew to your shell:

```bash
echo >> /home/openclaw/.bashrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> /home/openclaw/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"
```

### Step 4: Verify Installation

```bash
brew --version
```

### Installing Packages

Once Homebrew is installed, you can install packages:

```bash
brew install <package-name>
```

**Note:** Homebrew packages are installed to `/home/linuxbrew/.linuxbrew/` and are available to all users on the system.

## Memory Configuration with Ollama

OpenClaw's memory search requires an embedding provider to index and search through your memory files. Ollama is an excellent choice for local, offline operation.

### Prerequisites

1. **Install Ollama** on your Proxmox host or a separate server:

   ```bash
   # On the OpenClaw container or a separate server
   curl -fsSL https://ollama.com/install.sh | sh
   ```

2. **Pull an embedding model**. Recommended models for embeddings:

   ```bash
   # nomic-embed-text (recommended - good balance of quality and speed)
   ollama pull nomic-embed-text

   # Alternative: mxbai-embed-large (larger, more accurate)
   ollama pull mxbai-embed-large

   # Alternative: all-minilm (smaller, faster)
   ollama pull all-minilm
   ```

### Configure OpenClaw for Ollama

#### Option 1: Edit Configuration File

```bash
# Edit as the openclaw user
su - openclaw
nano ~/.openclaw/openclaw.json
```

Add the memory search configuration:

```json
{
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "token": "your-token-here"
    },
    "controlUi": {
      "allowedOrigins": [
        "http://localhost:18789",
        "http://127.0.0.1:18789",
        "https://localhost:18790",
        "https://127.0.0.1:18790"
      ]
    }
  },
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "ollama",
        "model": "nomic-embed-text",
        "remote": {
          "baseUrl": "http://localhost:11434"
        }
      }
    }
  }
}
```

#### Option 2: Use OpenClaw CLI

```bash
# Configure memory search provider
openclaw configure --section agents.defaults.memorySearch

# Set provider to ollama
openclaw configure --set agents.defaults.memorySearch.provider=ollama
openclaw configure --set agents.defaults.memorySearch.model=nomic-embed-text
openclaw configure --set agents.defaults.memorySearch.remote.baseUrl=http://localhost:11434
```

### Ollama on a Separate Server

If Ollama runs on a different server, update the `baseUrl`:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "ollama",
        "model": "nomic-embed-text",
        "remote": {
          "baseUrl": "http://192.168.1.100:11434"
        }
      }
    }
  }
}
```

### Verify Memory Configuration

Check memory status:

```bash
openclaw memory status --deep
```

Expected output with Ollama configured:

```
Memory Search (main)
Provider: ollama
Model: nomic-embed-text
Sources: memory
Indexed: X/Y files · Z chunks
Store: ~/.openclaw/memory/main.sqlite
Embeddings: ready
```

### Create Memory Files

Memory files are Markdown files that OpenClaw indexes:

```bash
# Create memory directory
mkdir -p ~/.openclaw/workspace/memory

# Create your first memory file
cat > ~/.openclaw/workspace/MEMORY.md << 'EOF'
# Personal Memory

## Preferences
- I prefer concise responses
- Use bullet points for lists

## Projects
- Home automation: running on Proxmox
- Media server: Jellyfin on port 8096
EOF

# Create additional memory files
cat > ~/.openclaw/workspace/memory/projects.md << 'EOF'
# Project Details

## Home Lab
- Proxmox VE host: 192.168.1.10
- OpenClaw container: 192.168.1.20
- Storage: TrueNAS at 192.168.1.30
EOF
```

### Reindex Memory

Force a reindex after configuration changes:

```bash
openclaw memory reindex
```

### Troubleshooting Memory Issues

#### "No API key found" Error

This error appears when no embedding provider is configured. Solution:

```bash
# Configure Ollama as the embedding provider
openclaw configure --set agents.defaults.memorySearch.provider=ollama
openclaw configure --set agents.defaults.memorySearch.model=nomic-embed-text
```

#### "memory directory missing" Warning

Create the memory workspace:

```bash
mkdir -p ~/.openclaw/workspace/memory
```

#### Ollama Connection Refused

Ensure Ollama is running and accessible:

```bash
# Check Ollama status
systemctl status ollama

# Test Ollama API
curl http://localhost:11434/api/tags

# If running on a separate server, check firewall
ufw allow 11434/tcp
```

#### Slow First Search

The first search may be slow as OpenClaw indexes your memory files. Subsequent searches use cached embeddings.

### Embedding Model Comparison

| Model             | Size   | Quality | Speed   | Use Case                      |
| ----------------- | ------ | ------- | ------- | ----------------------------- |
| nomic-embed-text  | ~274MB | Good    | Fast    | General purpose (recommended) |
| mxbai-embed-large | ~670MB | Better  | Medium  | Higher accuracy needed        |
| all-minilm        | ~45MB  | Basic   | Fastest | Resource-constrained          |

### Hybrid Search (BM25 + Vector)

Enable hybrid search for better recall:

```json
{
  "agents": {
    "defaults": {
      "memorySearch": {
        "provider": "ollama",
        "model": "nomic-embed-text",
        "remote": {
          "baseUrl": "http://localhost:11434"
        },
        "query": {
          "hybrid": {
            "enabled": true,
            "vectorWeight": 0.7,
            "textWeight": 0.3
          }
        }
      }
    }
  }
}
```

### Additional Resources

- [OpenClaw Gateway Documentation](https://docs.openclaw.ai/gateway)
- [OpenClaw Security Guide](https://docs.openclaw.ai/gateway/security)
- [OpenClaw Troubleshooting](https://docs.openclaw.ai/gateway/troubleshooting)
- [OpenClaw Memory Configuration Reference](https://docs.openclaw.ai/reference/memory-config)
- [Ollama Documentation](https://ollama.com/docs)
