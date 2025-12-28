#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: snazzybean
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/TomBursch/kitchenowl

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  nginx \
  build-essential \
  libpq-dev \
  libffi-dev \
  libssl-dev
msg_ok "Installed Dependencies"

PYTHON_VERSION="3.12" setup_uv

msg_info "Downloading KitchenOwl Backend"
RELEASE=$(curl -fsSL https://api.github.com/repos/TomBursch/kitchenowl/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
mkdir -p /opt/kitchenowl
curl -fsSL "https://github.com/TomBursch/kitchenowl/archive/refs/tags/v${RELEASE}.tar.gz" -o /tmp/kitchenowl.tar.gz
tar -xzf /tmp/kitchenowl.tar.gz -C /tmp
mv /tmp/kitchenowl-${RELEASE}/backend /opt/kitchenowl/backend
rm -rf /tmp/kitchenowl.tar.gz /tmp/kitchenowl-${RELEASE}
echo "${RELEASE}" >"$HOME/.kitchenowl"
msg_ok "Downloaded KitchenOwl Backend"

msg_info "Downloading KitchenOwl Frontend"
curl -fsSL "https://github.com/TomBursch/kitchenowl/releases/download/v${RELEASE}/kitchenowl_Web.tar.gz" -o /tmp/kitchenowl_web.tar.gz
mkdir -p /opt/kitchenowl/web
tar -xzf /tmp/kitchenowl_web.tar.gz -C /opt/kitchenowl/web
rm -f /tmp/kitchenowl_web.tar.gz
msg_ok "Downloaded KitchenOwl Frontend"

msg_info "Installing Python Dependencies"
cd /opt/kitchenowl/backend
$STD uv sync --frozen
msg_ok "Installed Python Dependencies"

msg_info "Configuring Production Mode"
sed -i 's/default=True/default=False/' /opt/kitchenowl/backend/wsgi.py
msg_ok "Configured Production Mode"

msg_info "Downloading NLTK Data"
mkdir -p /nltk_data
cd /opt/kitchenowl/backend
$STD uv run python -m nltk.downloader -d /nltk_data averaged_perceptron_tagger_eng punkt_tab
msg_ok "Downloaded NLTK Data"

msg_info "Configuring KitchenOwl"
JWT_SECRET=$(openssl rand -hex 32)
CONTAINER_IP=$(hostname -I | awk '{print $1}')
mkdir -p /opt/kitchenowl/data

cat <<EOF >/opt/kitchenowl/kitchenowl.env
STORAGE_PATH=/opt/kitchenowl/data
JWT_SECRET_KEY=${JWT_SECRET}
NLTK_DATA=/nltk_data
FRONT_URL=http://${CONTAINER_IP}
FLASK_APP=wsgi.py
FLASK_ENV=production
EOF
msg_ok "Configured KitchenOwl"

msg_info "Initializing Database"
cd /opt/kitchenowl/backend
export STORAGE_PATH=/opt/kitchenowl/data
export JWT_SECRET_KEY=${JWT_SECRET}
export NLTK_DATA=/nltk_data
export FRONT_URL=http://${CONTAINER_IP}
export FLASK_APP=wsgi.py
export FLASK_ENV=production
$STD uv run flask db upgrade
msg_ok "Initialized Database"

msg_info "Creating Systemd Service"
cat <<EOF >/etc/systemd/system/kitchenowl.service
[Unit]
Description=KitchenOwl Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/kitchenowl/backend
EnvironmentFile=/opt/kitchenowl/kitchenowl.env
ExecStart=/usr/local/bin/uv run wsgi.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now kitchenowl
msg_ok "Created and Started Service"

msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default
cat <<'EOF' >/etc/nginx/sites-available/kitchenowl.conf
server {
    listen 80;
    server_name _;

    root /opt/kitchenowl/web;
    index index.html;

    client_max_body_size 100M;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /api {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    location /socket.io {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        # WebSocket Timeouts - allow long-lived connections
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
EOF
ln -sf /etc/nginx/sites-available/kitchenowl.conf /etc/nginx/sites-enabled/
$STD systemctl reload nginx
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
