#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Derek & community contributors
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/alexmi256/rea-agent-docker | https://github.com/morluto/rea | https://github.com/openbin-ai/binny

COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main}"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")

APP="RE-Agent"
var_tags="${var_tags:-ai;malware;reverse-engineering;security;agent}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/ghidra ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Updating base packages"
  apt_update_safe
  $STD apt upgrade -y
  msg_ok "Base system updated"

  msg_info "Updating REA agents & MCP tools"
  $STD npm update -g rea-agents supergateway
  msg_ok "Updated REA tools"

  msg_info "Updating Hermes Agent"
  if [[ -x /home/analyst/.local/bin/hermes ]]; then
    su - analyst -c '/home/analyst/.local/bin/hermes update --yes' >/dev/null 2>&1 || true
    systemctl restart hermes-dashboard hermes-gateway 2>/dev/null || true
  fi
  msg_ok "Updated Hermes Agent"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access the Hermes Web Dashboard:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9119${CL}"
echo -e "${INFO}${YW} Hermes Gateway API: ${BGN}http://${IP}:8642${CL}"
echo -e "${INFO}${YW} Workspace directory: ${BGN}/work/cases${CL}"
echo -e "${TAB}${GN}💡 Use 'rea-case new <sample>' to start a stateless investigation.${CL}"
