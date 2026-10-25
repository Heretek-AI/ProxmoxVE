#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Derek & community contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alexmi256/rea-agent-docker | https://github.com/morluto/rea | https://github.com/openbin-ai/binny

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH" 2>/dev/null || true
if ! declare -f msg_info >/dev/null 2>&1; then
  # Standalone fallback functions if executed directly
  YW=$(echo "\033[33m")
  BL=$(echo "\033[36m")
  RD=$(echo "\033[01;31m")
  BGN=$(echo "\033[4;92m")
  GN=$(echo "\033[1;92m")
  CL=$(echo "\033[m")
  msg_info() { echo -e "${BL}[INFO]${CL} $*"; }
  msg_ok() { echo -e "${GN}[OK]${CL} $*"; }
  msg_warn() { echo -e "${YW}[WARN]${CL} $*"; }
  msg_error() { echo -e "${RD}[ERROR]${CL} $*"; }
  STD=""
fi

export DEBIAN_FRONTEND=noninteractive

msg_info "Updating base operating system packages"
apt-get update -y >/dev/null 2>&1
apt-get upgrade -y >/dev/null 2>&1
msg_ok "Updated base operating system"

msg_info "Installing core reverse-engineering system dependencies"
apt-get install -y --no-install-recommends \
  curl \
  wget \
  git \
  jq \
  file \
  tar \
  unzip \
  p7zip-full \
  build-essential \
  pkg-config \
  libssl-dev \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  iptables \
  ipset \
  ca-certificates \
  gnupg \
  radare2 \
  upx-ucl \
  tshark \
  tcpdump \
  sudo >/dev/null 2>&1
msg_ok "Installed system dependencies"

# ------------------------------------------------------------------------------
# 1. OpenJDK 21 & Ghidra Headless Engine
# ------------------------------------------------------------------------------
msg_info "Installing OpenJDK 21 Headless for Ghidra"
apt-get install -y --no-install-recommends openjdk-21-jdk-headless >/dev/null 2>&1
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
msg_ok "Installed OpenJDK 21 Headless"

msg_info "Downloading and deploying Ghidra"
GHIDRA_DIR="/opt/ghidra"
if [[ ! -d "$GHIDRA_DIR" ]]; then
  mkdir -p "$GHIDRA_DIR"
  GHIDRA_TAG=$(curl -s https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest | jq -r '.tag_name' 2>/dev/null || echo "Ghidra_11.2.1_build")
  GHIDRA_URL=$(curl -s https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest | jq -r '.assets[] | select(.name | test("ghidra_.*_PUBLIC_.*\\.zip")) | .browser_download_url' 2>/dev/null | head -1)
  
  if [[ -z "$GHIDRA_URL" || "$GHIDRA_URL" == "null" ]]; then
    GHIDRA_URL="https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_11.2.1_build/ghidra_11.2.1_PUBLIC_20241105.zip"
  fi

  TMP_ZIP="/tmp/ghidra.zip"
  wget -q -O "$TMP_ZIP" "$GHIDRA_URL" || curl -fsSL -o "$TMP_ZIP" "$GHIDRA_URL"
  unzip -q "$TMP_ZIP" -d /opt/
  rm -f "$TMP_ZIP"
  
  EXTRACTED_DIR=$(find /opt -maxdepth 1 -type d -name "ghidra_*_PUBLIC" | head -1)
  if [[ -n "$EXTRACTED_DIR" ]]; then
    mv "$EXTRACTED_DIR"/* "$GHIDRA_DIR"/
    rm -rf "$EXTRACTED_DIR"
  fi
  chmod +x "$GHIDRA_DIR"/support/analyzeHeadless "$GHIDRA_DIR"/ghidraRun 2>/dev/null || true
  msg_ok "Ghidra deployed to $GHIDRA_DIR"
else
  msg_ok "Ghidra already present in $GHIDRA_DIR"
fi

# Configure environment exports for Ghidra
cat << 'EOF' > /etc/profile.d/re-agent.sh
export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
export GHIDRA_INSTALL_DIR="/opt/ghidra"
export GHIDRA_HEADLESS_MAXMEM="4G"
export PATH="$PATH:/opt/ghidra/support:/usr/local/bin"
EOF
chmod 644 /etc/profile.d/re-agent.sh
source /etc/profile.d/re-agent.sh

# ------------------------------------------------------------------------------
# 2. Node.js 22 LTS & REA (Reverse Engineer Anything)
# ------------------------------------------------------------------------------
msg_info "Installing Node.js 22 LTS"
if ! command -v node >/dev/null 2>&1 || [[ $(node -v | cut -d'.' -f1 | tr -d 'v') -lt 20 ]]; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg --yes 2>/dev/null
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
  apt-get update -y >/dev/null 2>&1
  apt-get install -y nodejs >/dev/null 2>&1
fi
msg_ok "Installed Node.js $(node -v 2>/dev/null)"

msg_info "Installing REA (rea-agents) and MCP tools globally"
npm install -g rea-agents supergateway >/dev/null 2>&1
msg_ok "Installed rea-agents and supergateway"

# ------------------------------------------------------------------------------
# 3. Static Malware Triage Toolchain (CAPA, FLOSS, YARA, DIEC)
# ------------------------------------------------------------------------------
msg_info "Deploying static malware triage toolchain"
mkdir -p /opt/triage-tools /opt/triage-tools/rules

# Python RE Virtual Environment with uv/pip
python3 -m venv /opt/re-tools-venv
/opt/re-tools-venv/bin/pip install --upgrade pip wheel >/dev/null 2>&1
/opt/re-tools-venv/bin/pip install --no-cache-dir \
  flare-capa \
  flare-floss \
  yara-python \
  pefile \
  pwntools \
  pyelftools \
  r2pipe >/dev/null 2>&1

# Link binaries into system path
ln -sf /opt/re-tools-venv/bin/capa /usr/local/bin/capa
ln -sf /opt/re-tools-venv/bin/floss /usr/local/bin/floss

# Detect It Easy CLI (diec)
DIEC_URL=$(curl -s https://api.github.com/repos/horsicq/DIE-engine/releases/latest | jq -r '.assets[] | select(.name | test("die_.*_Ubuntu_.*_amd64\\.deb")) | .browser_download_url' 2>/dev/null | head -1)
if [[ -n "$DIEC_URL" && "$DIEC_URL" != "null" ]]; then
  wget -q -O /tmp/diec.deb "$DIEC_URL" 2>/dev/null && dpkg -i /tmp/diec.deb >/dev/null 2>&1 || true
  rm -f /tmp/diec.deb
fi
msg_ok "Deployed CAPA, FLOSS, YARA, and PE analysis tools"

# ------------------------------------------------------------------------------
# 4. OpenBin BINNY RE Agent Harness
# ------------------------------------------------------------------------------
msg_info "Installing OpenBin BINNY agent harness"
BINNY_BIN_URL=$(curl -s https://api.github.com/repos/openbin-ai/binny/releases/latest | jq -r '.assets[] | select(.name | test("binny-.*linux.*amd64")) | .browser_download_url' 2>/dev/null | head -1)
if [[ -n "$BINNY_BIN_URL" && "$BINNY_BIN_URL" != "null" ]]; then
  wget -q -O /usr/local/bin/binny "$BINNY_BIN_URL"
  chmod +x /usr/local/bin/binny
else
  # Fallback to official install script
  curl -fsSL https://openbin.ai/install-binny.sh 2>/dev/null | sh >/dev/null 2>&1 || true
fi
msg_ok "Configured OpenBin BINNY"

# ------------------------------------------------------------------------------
# 5. REA Casebook Evidence Tracker (pablodiazjorge/rea-casebook)
# ------------------------------------------------------------------------------
msg_info "Deploying REA Casebook evidence validation engine"
cat << 'CASEBOOK_SCRIPT' > /usr/local/bin/rea-casebook
#!/usr/bin/env python3
"""
REA Casebook - Verifiable Evidence Tracker for AI Reverse Engineering
Ensures AI agents cite verifiable evidence_id tokens rather than hallucinating.
"""
import sys
import os
import json
import time

def init_casebook(case_dir, sample_path):
    os.makedirs(case_dir, exist_ok=True)
    casebook_path = os.path.join(case_dir, "casebook.json")
    if not os.path.exists(casebook_path):
        data = {
            "sample": os.path.abspath(sample_path),
            "created_at": time.time(),
            "evidence": {},
            "verified_claims": []
        }
        with open(casebook_path, "w") as f:
            json.dump(data, f, indent=2)
    print(f"[CASEBOOK] Initialized casebook at {casebook_path}")

def record_evidence(case_dir, evidence_id, category, content, offset=None):
    casebook_path = os.path.join(case_dir, "casebook.json")
    if not os.path.exists(casebook_path):
        print(f"[ERROR] Casebook not found at {casebook_path}", file=sys.stderr)
        sys.exit(1)
    with open(casebook_path, "r") as f:
        data = json.load(f)
    data["evidence"][evidence_id] = {
        "category": category,
        "content": content,
        "offset": offset,
        "timestamp": time.time()
    }
    with open(casebook_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"[CASEBOOK] Recorded evidence: {evidence_id}")

def verify_claim(case_dir, claim_text, required_evidence_ids):
    casebook_path = os.path.join(case_dir, "casebook.json")
    with open(casebook_path, "r") as f:
        data = json.load(f)
    missing = [eid for eid in required_evidence_ids if eid not in data["evidence"]]
    if missing:
        print(f"[REJECTED] Claim rejected! Missing evidence IDs: {missing}", file=sys.stderr)
        return False
    data["verified_claims"].append({
        "claim": claim_text,
        "evidence_ids": required_evidence_ids,
        "timestamp": time.time()
    })
    with open(casebook_path, "w") as f:
        json.dump(data, f, indent=2)
    print(f"[ACCEPTED] Claim verified with {len(required_evidence_ids)} citations.")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: rea-casebook [init|record|verify] [args...]")
        sys.exit(1)
    cmd = sys.argv[1]
    if cmd == "init" and len(sys.argv) >= 4:
        init_casebook(sys.argv[2], sys.argv[3])
    elif cmd == "record" and len(sys.argv) >= 6:
        record_evidence(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6] if len(sys.argv) > 6 else None)
    elif cmd == "verify" and len(sys.argv) >= 5:
        claim = sys.argv[3]
        eids = sys.argv[4].split(",")
        ok = verify_claim(sys.argv[2], claim, eids)
        sys.exit(0 if ok else 1)
CASEBOOK_SCRIPT
chmod +x /usr/local/bin/rea-casebook
msg_ok "Deployed REA Casebook verification engine"

# ------------------------------------------------------------------------------
# 6. User Account & Hermes Agent (Nous Research) Setup
# ------------------------------------------------------------------------------
msg_info "Creating analyst workspace user"
id -u analyst >/dev/null 2>&1 || useradd -m -s /bin/bash analyst
echo "analyst ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/analyst
chmod 440 /etc/sudoers.d/analyst
loginctl enable-linger analyst 2>/dev/null || true

mkdir -p /work /work/samples /work/cases
chown -R analyst:analyst /work
msg_ok "Created analyst user and /work environment"

msg_info "Installing Hermes Agent for analyst"
su - analyst -c '
  mkdir -p ~/.hermes
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o /tmp/hermes-install.sh 2>/dev/null || true
  if [[ -f /tmp/hermes-install.sh ]]; then
    bash /tmp/hermes-install.sh --skip-setup --hermes-home ~/.hermes --dir ~/.hermes/hermes-agent >/dev/null 2>&1 || true
    rm -f /tmp/hermes-install.sh
  fi
'

# Prewire REA plugin into Hermes Agent
su - analyst -c '
  export PATH=$PATH:~/.local/bin
  if command -v hermes >/dev/null 2>&1; then
    hermes plugins install rea >/dev/null 2>&1 || true
  fi
'

# Configure Hermes systemd services
cat << EOF > /etc/systemd/system/hermes-dashboard.service
[Unit]
Description=Hermes Agent Web Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=analyst
Group=analyst
WorkingDirectory=/home/analyst
ExecStart=/home/analyst/.local/bin/hermes dashboard --host 0.0.0.0 --port 9119 --no-open
Restart=on-failure
RestartSec=5
Environment=PATH=/home/analyst/.local/bin:/usr/local/bin:/usr/bin:/bin:/opt/ghidra/support
Environment=GHIDRA_INSTALL_DIR=/opt/ghidra
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

[Install]
WantedBy=multi-user.target
EOF

cat << EOF > /etc/systemd/system/hermes-gateway.service
[Unit]
Description=Hermes Agent Gateway API Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=analyst
Group=analyst
WorkingDirectory=/home/analyst
ExecStart=/home/analyst/.local/bin/hermes gateway run
Restart=on-failure
RestartSec=5
Environment=PATH=/home/analyst/.local/bin:/usr/local/bin:/usr/bin:/bin:/opt/ghidra/support
Environment=GHIDRA_INSTALL_DIR=/opt/ghidra
Environment=JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hermes-dashboard.service >/dev/null 2>&1 || true
systemctl start hermes-dashboard.service >/dev/null 2>&1 || true
msg_ok "Configured Hermes Agent with REA plugin on ports 9119 and 8642"

# ------------------------------------------------------------------------------
# 7. Stateless Case Manager CLI (/usr/local/bin/rea-case)
# ------------------------------------------------------------------------------
msg_info "Deploying Stateless Case Directory Orchestrator (rea-case)"
cat << 'REACASE' > /usr/local/bin/rea-case
#!/usr/bin/env bash
set -e

COMMAND="${1:-help}"
SAMPLE="${2:-}"

function usage() {
  echo "Usage: rea-case <command> [sample_file]"
  echo ""
  echo "Commands:"
  echo "  new <file>      Initialize a new stateless case directory and run automated triage"
  echo "  status <sample> Show current verified claims, findings, and hypothesis queue"
  echo "  export <sample> Export structured casebook to Markdown report"
  echo "  clean           Purge temporary decompilation and IDA/Ghidra lock files"
  exit 1
}

case "$COMMAND" in
  new)
    if [[ -z "$SAMPLE" || ! -f "$SAMPLE" ]]; then
      echo "Error: Target binary sample not found: $SAMPLE"
      exit 1
    fi
    SAMPLE_NAME=$(basename "$SAMPLE")
    CASE_DIR="/work/cases/${SAMPLE_NAME}"
    mkdir -p "$CASE_DIR"

    echo "==> [1/5] Calculating hashes..."
    MD5=$(md5sum "$SAMPLE" | awk '{print $1}')
    SHA256=$(sha256sum "$SAMPLE" | awk '{print $1}')
    FILE_TYPE=$(file -b "$SAMPLE")
    FILE_SIZE=$(stat -c%s "$SAMPLE")

    cat << EOF > "$CASE_DIR/metadata.json"
{
  "sample_name": "$SAMPLE_NAME",
  "file_path": "$SAMPLE",
  "file_size_bytes": $FILE_SIZE,
  "file_type": "$FILE_TYPE",
  "md5": "$MD5",
  "sha256": "$SHA256",
  "created_at": $(date +%s)
}
EOF

    echo "==> [2/5] Initializing REA Casebook..."
    /usr/local/bin/rea-casebook init "$CASE_DIR" "$SAMPLE"

    echo "==> [3/5] Running CAPA capability detection..."
    if command -v capa >/dev/null 2>&1; then
      capa -q "$SAMPLE" > "$CASE_DIR/capa_triage.txt" 2>&1 || true
    fi

    echo "==> [4/5] Extracting deobfuscated strings (FLOSS)..."
    if command -v floss >/dev/null 2>&1; then
      floss --quiet "$SAMPLE" > "$CASE_DIR/floss_strings.txt" 2>&1 || true
    fi

    echo "==> [5/5] Generating initial stateless investigation plan..."
    cat << EOF > "$CASE_DIR/investigation_plan.md"
# Investigation Plan: $SAMPLE_NAME

## Metadata
- **Type**: $FILE_TYPE
- **Size**: $FILE_SIZE bytes
- **SHA256**: \`$SHA256\`

## Triage Summary
- Capabilities detected in \`capa_triage.txt\`
- Deobfuscated strings in \`floss_strings.txt\`

## Hypothesis Queue (Episodic Subtasks)
- [ ] Subtask 1: Parse entry point and imports
- [ ] Subtask 2: Identify decryptors, unpacking loops, and strings
- [ ] Subtask 3: Analyze C2 communication and protocol framing
- [ ] Subtask 4: Map persistence or privilege escalation mechanisms

## Verified Findings
*(All findings must cite verified evidence_id from casebook.json)*
EOF

    echo "==> Case initialized at: $CASE_DIR"
    echo "    Agents can now inspect with zero context memory bloat."
    ;;

  status)
    SAMPLE_NAME=$(basename "$SAMPLE")
    CASE_DIR="/work/cases/${SAMPLE_NAME}"
    if [[ ! -d "$CASE_DIR" ]]; then
      echo "Error: Case directory not found: $CASE_DIR"
      exit 1
    fi
    echo "=== Case Status: $SAMPLE_NAME ==="
    cat "$CASE_DIR/metadata.json" | jq .
    if [[ -f "$CASE_DIR/casebook.json" ]]; then
      echo ""
      echo "Verified Claims:"
      jq '.verified_claims' "$CASE_DIR/casebook.json"
    fi
    ;;

  export)
    SAMPLE_NAME=$(basename "$SAMPLE")
    CASE_DIR="/work/cases/${SAMPLE_NAME}"
    REPORT_FILE="$CASE_DIR/FINAL_REPORT.md"
    echo "# Clean-Room Technical Report: $SAMPLE_NAME" > "$REPORT_FILE"
    echo "Generated: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    cat "$CASE_DIR/investigation_plan.md" >> "$REPORT_FILE"
    echo "Report exported to $REPORT_FILE"
    ;;

  clean)
    find /work -name "*.lock" -delete 2>/dev/null || true
    find /work -name "*.gpr" -delete 2>/dev/null || true
    echo "Purged temporary locks and caches."
    ;;

  *)
    usage
    ;;
esac
REACASE
chmod +x /usr/local/bin/rea-case
msg_ok "Deployed /usr/local/bin/rea-case"

# ------------------------------------------------------------------------------
# 8. Network Quarantine & Egress Proxy Helper (/usr/local/bin/re-firewall)
# ------------------------------------------------------------------------------
msg_info "Deploying network isolation and egress proxy manager"
cat << 'FIREWALL_SCRIPT' > /usr/local/bin/re-firewall
#!/usr/bin/env bash
set -e

ACTION="${1:-status}"
PROXY_IP="${2:-10.99.0.1}"
PROXY_PORT="${3:-8080}"

case "$ACTION" in
  isolate)
    echo "==> Enforcing strict network quarantine..."
    ANALYST_UID=$(id -u analyst 2>/dev/null || echo 1000)

    # Flush current custom chains
    iptables -F OUTPUT 2>/dev/null || true

    # Allow loopback unconditionally
    iptables -A OUTPUT -o lo -j ACCEPT

    # Allow established connections
    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Allow ONLY the analyst user to reach the designated Egress Proxy
    iptables -A OUTPUT -p tcp -m owner --uid-owner "$ANALYST_UID" -d "$PROXY_IP" --dport "$PROXY_PORT" -j ACCEPT

    # Block all private LAN subnets (RFC 1918)
    iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
    iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
    iptables -A OUTPUT -d 192.168.0.0/16 -j DROP

    # Drop all other outbound traffic from any user, sandbox, or dynamic process
    iptables -A OUTPUT -j DROP

    echo "==> Quarantine ACTIVE: Only UID $ANALYST_UID can egress to $PROXY_IP:$PROXY_PORT (LLM Proxy)."
    echo "    All other outbound traffic and LAN packets are BLOCKED."
    ;;

  unmask)
    echo "==> Restoring default unrestricted networking..."
    iptables -F OUTPUT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
    echo "==> Network unmasked (development / update mode)."
    ;;

  status)
    echo "=== Outbound Firewall Filter Status ==="
    iptables -L OUTPUT -v -n --line-numbers
    ;;

  *)
    echo "Usage: re-firewall [isolate <proxy_ip> <proxy_port> | unmask | status]"
    exit 1
    ;;
esac
FIREWALL_SCRIPT
chmod +x /usr/local/bin/re-firewall
msg_ok "Deployed /usr/local/bin/re-firewall"

# ------------------------------------------------------------------------------
# 9. Host-Side Proxy Template
# ------------------------------------------------------------------------------
mkdir -p /opt/re-agent
cat << 'PROXY_CONF' > /opt/re-agent/host-egress-proxy.conf
# Sample Squid / Forward Proxy configuration for the Proxmox Host or Gateway
# Restricts VM egress to whitelisted remote LLM providers only.
http_port 8080

acl allowed_llm dstdomain .anthropic.com
acl allowed_llm dstdomain .openai.com
acl allowed_llm dstdomain .openrouter.ai
acl allowed_llm dstdomain .googleapis.com

# Allow SSL connect only to LLM ports
acl SSL_ports port 443
acl Safe_ports port 443
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

# Enforce domain whitelist
http_access allow allowed_llm
http_access deny all
PROXY_CONF

msg_ok "Installation completed successfully!"
