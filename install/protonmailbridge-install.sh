#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: kevinwoodland
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ProtonMail/proton-bridge

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  pass \
  gnupg \
  socat \
  libsecret-1-0
msg_ok "Installed Dependencies"

msg_info "Configuring GPG and Pass for Credential Storage"
gpg --batch --passphrase '' --quick-gen-key 'ProtonMail Bridge' default default never
pass init "ProtonMail Bridge"
msg_ok "Configured GPG and Pass"

fetch_and_deploy_gh_release "protonmail-bridge" "ProtonMail/proton-bridge" "binary" "latest" "" "protonmail-bridge_*_amd64.deb"

msg_info "Creating Proton Mail Bridge Service"
cat <<EOF >/etc/systemd/system/protonmail-bridge.service
[Unit]
Description=Proton Mail Bridge
After=network.target

[Service]
Type=simple
Environment=HOME=/root
ExecStart=/usr/bin/protonmail-bridge --no-window --noninteractive
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Proton Mail Bridge Service"

msg_info "Creating Proxy Services"
cat <<EOF >/etc/systemd/system/protonmail-bridge-imap.service
[Unit]
Description=Proton Mail Bridge IMAP Proxy
After=protonmail-bridge.service
Requires=protonmail-bridge.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:11143,fork,reuseaddr,bind=0.0.0.0 TCP4:127.0.0.1:1143
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >/etc/systemd/system/protonmail-bridge-smtp.service
[Unit]
Description=Proton Mail Bridge SMTP Proxy
After=protonmail-bridge.service
Requires=protonmail-bridge.service

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP4-LISTEN:11025,fork,reuseaddr,bind=0.0.0.0 TCP4:127.0.0.1:1025
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
msg_ok "Created Proxy Services"

msg_info "Creating Setup Helper"
cat <<'EOF' >/usr/local/bin/protonmail-setup
#!/bin/bash
echo "Stopping bridge service..."
systemctl stop protonmail-bridge 2>/dev/null

echo ""
echo "Starting Proton Mail Bridge CLI..."
echo "Commands: 'login' to add account, 'info' to show credentials, 'exit' to finish"
echo ""

protonmail-bridge --cli

echo ""
echo "Starting services..."
systemctl start protonmail-bridge
sleep 5
systemctl start protonmail-bridge-imap protonmail-bridge-smtp 2>/dev/null

echo ""
echo "Status:"
systemctl is-active --quiet protonmail-bridge && echo "  Bridge: running" || echo "  Bridge: stopped"
systemctl is-active --quiet protonmail-bridge-imap && echo "  IMAP Proxy (11143): running" || echo "  IMAP Proxy: stopped"
systemctl is-active --quiet protonmail-bridge-smtp && echo "  SMTP Proxy (11025): running" || echo "  SMTP Proxy: stopped"
EOF
chmod +x /usr/local/bin/protonmail-setup
msg_ok "Created Setup Helper"

msg_info "Enabling Services"
$STD systemctl daemon-reload
$STD systemctl enable protonmail-bridge
$STD systemctl enable protonmail-bridge-imap
$STD systemctl enable protonmail-bridge-smtp
msg_ok "Enabled Services"

motd_ssh
customize
cleanup_lxc
