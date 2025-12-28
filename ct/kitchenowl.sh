#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: snazzybean
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/TomBursch/kitchenowl

APP="KitchenOwl"
var_tags="${var_tags:-food;recipes}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d /opt/kitchenowl ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "kitchenowl" "TomBursch/kitchenowl"; then
    RELEASE=$(get_latest_github_release "TomBursch/kitchenowl")

    msg_info "Stopping Service"
    systemctl stop kitchenowl
    msg_ok "Stopped Service"

    msg_info "Backing up Data and Configuration"
    mkdir -p /opt/kitchenowl_backup
    cp -r /opt/kitchenowl/data /opt/kitchenowl_backup/
    cp -f /opt/kitchenowl/kitchenowl.env /opt/kitchenowl_backup/
    msg_ok "Backup completed to /opt/kitchenowl_backup"

    msg_info "Updating Backend"
    if ! curl -fsSL "https://github.com/TomBursch/kitchenowl/archive/refs/tags/v${RELEASE}.tar.gz" -o /tmp/kitchenowl.tar.gz; then
      msg_error "Failed to download backend!"
      exit 1
    fi
    if ! tar -xzf /tmp/kitchenowl.tar.gz -C /tmp; then
      msg_error "Failed to extract backend!"
      rm -f /tmp/kitchenowl.tar.gz
      exit 1
    fi
    rm -rf /opt/kitchenowl/backend
    mv /tmp/kitchenowl-${RELEASE}/backend /opt/kitchenowl/backend
    rm -rf /tmp/kitchenowl.tar.gz /tmp/kitchenowl-${RELEASE}
    sed -i 's/default=True/default=False/' /opt/kitchenowl/backend/wsgi.py
    msg_ok "Updated Backend"

    msg_info "Updating Frontend"
    if ! curl -fsSL "https://github.com/TomBursch/kitchenowl/releases/download/v${RELEASE}/kitchenowl_Web.tar.gz" -o /tmp/kitchenowl_web.tar.gz; then
      msg_error "Failed to download frontend!"
      exit 1
    fi
    rm -rf /opt/kitchenowl/web
    mkdir -p /opt/kitchenowl/web
    if ! tar -xzf /tmp/kitchenowl_web.tar.gz -C /opt/kitchenowl/web; then
      msg_error "Failed to extract frontend!"
      exit 1
    fi
    rm -f /tmp/kitchenowl_web.tar.gz
    msg_ok "Updated Frontend"

    msg_info "Installing Python Dependencies"
    cd /opt/kitchenowl/backend
    $STD uv sync --frozen
    msg_ok "Installed Python Dependencies"

    msg_info "Running Database Migrations"
    cd /opt/kitchenowl/backend || exit 1
    set -a
    source /opt/kitchenowl/kitchenowl.env
    set +a
    $STD uv run flask db upgrade
    msg_ok "Ran Database Migrations"

    msg_info "Starting Service"
    systemctl start kitchenowl
    msg_ok "Started Service"

    echo "${RELEASE}" >"$HOME/.kitchenowl"
    msg_ok "Updated successfully to v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
