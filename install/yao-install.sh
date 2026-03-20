#!/usr/bin/env bash

# Author: Heretek-AI
# License: MIT | https://github.com/Heretek-AI/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/YaoApp/yao

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
  unzip
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "yao" "YaoApp/yao" "singlefile" "latest" "/usr/local/bin" "yao-*-linux-*"

msg_info "Creating Application Directory"
if [[ -e /root/.yao && ! -d /root/.yao ]]; then
  rm -f /root/.yao
fi
mkdir -p /root/.yao/bin
msg_ok "Created Application Directory"

msg_info "Initializing Yao Application"
cd /root/.yao/bin
$STD /usr/local/bin/yao start
msg_ok "Initialized Yao Application"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/yao.service
[Unit]
Description=Yao - Autonomous Agent Engine
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/.yao/bin
ExecStart=/usr/local/bin/yao start
Restart=on-failure
RestartSec=5
Environment=YAO_PORT=5099
Environment=YAO_STUDIO_PORT=5077

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now yao
msg_ok "Created Service"

motd_ssh
customize
cleanup_lxc
