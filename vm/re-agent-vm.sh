#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Derek & community contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

# ==============================================================================
# RE-Agent VM - Hardened Reverse Engineering & Malware Analysis Agentic Appliance
# ==============================================================================

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}"
source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/pve/vm-core.func")
load_functions

# ==============================================================================
# SCRIPT VARIABLES
# ==============================================================================
APP="RE-Agent"
APP_TYPE="vm"
NSAPP="re-agent-vm"
var_os="debian"
var_version="13"
ARCH=$(dpkg --print-architecture)

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD=""
DISK_SIZE="40G"
USE_CLOUD_INIT="no"
OS_TYPE=""
OS_VERSION=""
THIN="discard=on,ssd=1,"
var_arm64="yes"

# ==============================================================================
# ERROR HANDLING & CLEANUP
# ==============================================================================
set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT
trap 'post_update_to_api "failed" "130"' SIGINT
trap 'post_update_to_api "failed" "143"' SIGTERM
trap 'post_update_to_api "failed" "129"; exit 129' SIGHUP

# ==============================================================================
# OS SELECTION FUNCTIONS
# ==============================================================================
function select_os() {
  if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
    OS_CHOICE="${VM_OS_VERSION:-debian13}"
  elif ! OS_CHOICE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "SELECT OS" --radiolist \
    "Choose Operating System for RE-Agent VM" 15 68 3 \
    "debian13" "Debian 13 (Trixie) - Recommended" ON \
    "ubuntu2404" "Ubuntu 24.04 LTS (Noble)" OFF \
    "debian12" "Debian 12 (Bookworm)" OFF \
    3>&1 1>&2 2>&3); then
    exit_script
  fi

  case $OS_CHOICE in
  debian13)
    OS_TYPE="debian"
    OS_VERSION="13"
    OS_CODENAME="trixie"
    OS_DISPLAY="Debian 13 (Trixie)"
    ;;
  ubuntu2404)
    OS_TYPE="ubuntu"
    OS_VERSION="24.04"
    OS_CODENAME="noble"
    OS_DISPLAY="Ubuntu 24.04 LTS"
    ;;
  debian12)
    OS_TYPE="debian"
    OS_VERSION="12"
    OS_CODENAME="bookworm"
    OS_DISPLAY="Debian 12 (Bookworm)"
    ;;
  *)
    msg_error "Unsupported OS '${OS_CHOICE}'"
    exit 1
    ;;
  esac
  echo -e "${OS}${BOLD}${DGN}Operating System: ${BGN}${OS_DISPLAY}${CL}"
}

function select_cloud_init() {
  vm_prompt_cloud_init "root"
  if [ "$OS_TYPE" = "ubuntu" ] && [ "$USE_CLOUD_INIT" != "yes" ]; then
    USE_CLOUD_INIT="yes"
    export CLOUDINIT_ENABLE="yes"
    msg_warn "Ubuntu requires Cloud-Init - enabling it automatically"
  fi
}

function get_image_url() {
  local arch=$(dpkg --print-architecture)
  case $OS_TYPE in
  debian)
    if [ "$USE_CLOUD_INIT" = "yes" ]; then
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-generic-${arch}.qcow2"
    else
      echo "https://cloud.debian.org/images/cloud/${OS_CODENAME}/latest/debian-${OS_VERSION}-nocloud-${arch}.qcow2"
    fi
    ;;
  ubuntu)
    echo "https://cloud-images.ubuntu.com/${OS_CODENAME}/current/${OS_CODENAME}-server-cloudimg-${arch}.img"
    ;;
  esac
}

# ==============================================================================
# SETTINGS FUNCTIONS
# ==============================================================================
function default_settings() {
  vm_apply_machine_type "q35"
  select_os
  select_cloud_init

  VMID=$(get_valid_nextid)
  if [ "$ARCH" = "arm64" ]; then
    CPU_TYPE=""
  else
    CPU_TYPE=" -cpu host"
  fi
  DISK_CACHE=""
  DISK_SIZE="40G"
  HN="re-agent"
  CORE_COUNT="4"
  RAM_SIZE="8192"
  BRG="vmbr0"
  MAC="$GEN_MAC"
  VLAN=""
  MTU=""
  START_VM="yes"
  METHOD="default"

  vm_echo_default_settings
}

function advanced_settings() {
  METHOD="advanced"
  select_os
  select_cloud_init

  vm_prompt_vmid
  vm_prompt_hostname "re-agent"
  vm_prompt_cpu_cores "4"
  vm_prompt_ram "8192"
  vm_prompt_bridge "vmbr0"
  vm_prompt_mac "$GEN_MAC"
  vm_prompt_vlan
  vm_prompt_mtu
  vm_prompt_disk_size "40"
  vm_prompt_storage
  vm_prompt_start_vm
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================
header_info "$APP"
vm_preflight

if [[ "${VM_UNATTENDED:-0}" == "1" ]]; then
  default_settings
elif (whiptail --backtitle "Proxmox VE Helper Scripts" --title "SETTINGS" --yesno \
  "Use Default Settings? (Debian 13, 4 vCPU, 8GB RAM, 40GB Disk, vmbr0)" 10 60); then
  default_settings
else
  advanced_settings
fi

# ==============================================================================
# PREREQUISITES
# ==============================================================================
vm_ensure_virt_customize
$STD apt-get -qq install lsb-release dhcpcd-base -y 2>/dev/null || true

# ==============================================================================
# IMAGE DOWNLOAD
# ==============================================================================
msg_info "Retrieving the URL for the ${OS_DISPLAY} Qcow2 Disk Image"
URL=$(get_image_url)
CACHE_DIR="/var/lib/vz/template/cache"
CACHE_FILE="$CACHE_DIR/$(basename "$URL")"
mkdir -p "$CACHE_DIR"
msg_ok "${CL}${BL}${URL}${CL}"

MIN_IMAGE_BYTES=$((100 * 1024 * 1024))
vm_fetch_image "$URL" "$CACHE_FILE" --cache --min-bytes "$MIN_IMAGE_BYTES" || exit 115

# ==============================================================================
# STORAGE TYPE DETECTION
# ==============================================================================
STORAGE_TYPE=$(pvesm status -storage "$STORAGE" | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
nfs | dir)
  DISK_EXT=".qcow2"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format qcow2"
  THIN=""
  ;;
btrfs)
  DISK_EXT=".raw"
  DISK_REF="$VMID/"
  DISK_IMPORT="--format raw"
  FORMAT=",efitype=4m"
  THIN=""
  ;;
*)
  DISK_EXT=""
  DISK_REF=""
  DISK_IMPORT="--format raw"
  ;;
esac

# ==============================================================================
# IMAGE CUSTOMIZATION
# ==============================================================================
msg_info "Preparing ${OS_DISPLAY} image for RE-Agent Appliance"

WORK_FILE=$(mktemp --suffix=.qcow2)
cp "$CACHE_FILE" "$WORK_FILE"

if [ "${USE_CLOUD_INIT:-no}" != "yes" ]; then
  msg_info "Expanding the root filesystem to ${DISK_SIZE}"
  vm_expand_image "$WORK_FILE" "$DISK_SIZE" || true
fi

export LIBGUESTFS_BACKEND_SETTINGS=dns=8.8.8.8,1.1.1.1

msg_info "Injecting base utilities and qemu-guest-agent"
virt-customize -q -a "$WORK_FILE" --install qemu-guest-agent,curl,wget,ca-certificates,sudo,git,jq >/dev/null 2>&1 || true

msg_info "Configuring first-boot provisioning service"
# Write the bootstrap installer directly into the image
virt-customize -q -a "$WORK_FILE" --run-command 'cat > /root/install-re-agent.sh << "SETUP_PAYLOAD"
#!/bin/bash
exec > /var/log/install-re-agent.log 2>&1
echo "[$(date)] Starting RE-Agent environment setup"

# Wait for internet connectivity
for i in {1..30}; do
  curl -s -I https://github.com >/dev/null 2>&1 && break
  sleep 2
done

# Fetch and execute the official re-agent install script
SCRIPT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/re-agent-install.sh"
curl -fsSL "$SCRIPT_URL" -o /tmp/re-agent-install.sh 2>/dev/null || true

if [[ -f /tmp/re-agent-install.sh ]]; then
  bash /tmp/re-agent-install.sh
  rm -f /tmp/re-agent-install.sh
else
  echo "[ERROR] Could not fetch re-agent-install.sh"
fi

touch /root/.re-agent-installed
echo "[$(date)] RE-Agent installation completed successfully"
SETUP_PAYLOAD
chmod +x /root/install-re-agent.sh' >/dev/null 2>&1 || true

virt-customize -q -a "$WORK_FILE" --run-command 'cat > /etc/systemd/system/install-re-agent.service << "EOF"
[Unit]
Description=First Boot RE-Agent Setup
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/root/.re-agent-installed

[Service]
Type=oneshot
ExecStart=/root/install-re-agent.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable install-re-agent.service' >/dev/null 2>&1 || true

msg_info "Finalizing image configuration"
vm_prepare_cloud_image "$WORK_FILE" "$HN" || true

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
  virt-customize -q -a "$WORK_FILE" --run-command "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config" >/dev/null 2>&1 || true
fi
msg_ok "Finalized disk image"

msg_info "Resizing disk image to ${DISK_SIZE}"
qemu-img resize "$WORK_FILE" "${DISK_SIZE}" >/dev/null 2>&1
msg_ok "Resized disk image"

# ==============================================================================
# VM CREATION
# ==============================================================================
msg_info "Creating RE-Agent VM shell"

qm create $VMID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $RAM_SIZE \
  -name $HN -tags community-script,ai,malware,reverse-engineering -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci >/dev/null

msg_ok "Created VM shell"

# ==============================================================================
# DISK IMPORT
# ==============================================================================
msg_info "Importing disk into storage ($STORAGE)"

if qm disk import --help >/dev/null 2>&1; then
  IMPORT_CMD=(qm disk import)
else
  IMPORT_CMD=(qm importdisk)
fi

IMPORT_OUT="$("${IMPORT_CMD[@]}" "$VMID" "$WORK_FILE" "$STORAGE" ${DISK_IMPORT:-} 2>&1 || true)"
DISK_REF_IMPORTED="$(printf '%s\n' "$IMPORT_OUT" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "\r\"'")"
[[ -z "$DISK_REF_IMPORTED" ]] && DISK_REF_IMPORTED="$(pvesm list "$STORAGE" | awk -v id="$VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
[[ -z "$DISK_REF_IMPORTED" ]] && {
  msg_error "Unable to determine imported disk reference."
  echo "$IMPORT_OUT"
  exit 226
}

msg_ok "Imported disk (${CL}${BL}${DISK_REF_IMPORTED}${CL})"
rm -f "$WORK_FILE"

# ==============================================================================
# VM CONFIGURATION
# ==============================================================================
msg_info "Attaching EFI and root disk"

qm set "$VMID" \
  --efidisk0 "${STORAGE}:0,efitype=4m" \
  --scsi0 "${DISK_REF_IMPORTED},${DISK_CACHE}${THIN%,}" \
  --boot order=scsi0 \
  --serial0 socket >/dev/null

qm set $VMID --agent enabled=1 >/dev/null
msg_ok "Attached EFI and root disk"

set_description

msg_info "Configuring Cloud-Init"
if vm_provision "$VMID"; then
  msg_ok "Cloud-Init configured"
else
  msg_warn "VM created, but not provisioned"
fi

if [ "$START_VM" == "yes" ]; then
  msg_info "Starting RE-Agent VM"
  $STD qm start $VMID
  msg_ok "Started RE-Agent VM"
fi

# ==============================================================================
# SNAPSHOT HOOK & FINAL OUTPUT
# ==============================================================================
VM_IP=""
if [ "$START_VM" == "yes" ]; then
  set +e
  for i in {1..15}; do
    VM_IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null |
      jq -r '.[] | select(.name != "lo") | ."ip-addresses"[]? | select(."ip-address-type" == "ipv4") | ."ip-address"' 2>/dev/null |
      grep -v "^127\." | head -1) || true
    [ -n "$VM_IP" ] && break
    sleep 3
  done
  set -e
fi

echo -e "\n${INFO}${BOLD}${GN}RE-Agent VM Configuration Summary:${CL}"
echo -e "${TAB}${DGN}VM ID: ${BGN}${VMID}${CL}"
echo -e "${TAB}${DGN}Hostname: ${BGN}${HN}${CL}"
echo -e "${TAB}${DGN}OS: ${BGN}${OS_DISPLAY}${CL}"
[ -n "$VM_IP" ] && echo -e "${TAB}${DGN}IP Address: ${BGN}${VM_IP}${CL}"
echo -e "${TAB}${DGN}Hermes Dashboard: ${BGN}http://${VM_IP:-<IP>}:9119${CL}"
echo -e "${TAB}${DGN}Hermes Gateway API: ${BGN}http://${VM_IP:-<IP>}:8642${CL}"
echo -e "${TAB}${YW}⚠️  Toolchain (Ghidra, REA, BINNY, Casebook) installs on first boot (3-5 mins)${CL}"
echo -e "${TAB}${YW}⚠️  Monitor progress: ${BL}tail -f /var/log/install-re-agent.log${CL}"
echo -e "${TAB}${GN}💡 Recommended: Once initialized, take a baseline snapshot:${CL}"
echo -e "${TAB}${TAB}${BL}qm snapshot ${VMID} baseline-clean --description 'Pristine RE Environment'${CL}"

if [ "$USE_CLOUD_INIT" = "yes" ]; then
  display_cloud_init_info "$VMID" "$HN" 2>/dev/null || true
fi

post_update_to_api "done" "none"
msg_ok "Completed successfully!\n"
