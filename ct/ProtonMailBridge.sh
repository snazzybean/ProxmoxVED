#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/snazzybean/ProxmoxVED/feat/proton-mail-bridge/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: kevinwoodland
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ProtonMail/proton-bridge

APP="Proton Mail Bridge"
var_tags="${var_tags:-email;smtp;imap;protonmail}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/bin/protonmail-bridge ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Proton Mail Bridge Services"
  $STD systemctl stop protonmail-bridge-proxy
  $STD systemctl stop protonmail-bridge
  msg_ok "Stopped Proton Mail Bridge Services"

  fetch_and_deploy_gh_release "protonmail-bridge" "ProtonMail/proton-bridge" "binary" "latest" "" "protonmail-bridge_*_amd64.deb"

  msg_info "Starting Proton Mail Bridge Services"
  $STD systemctl start protonmail-bridge
  sleep 5
  $STD systemctl start protonmail-bridge-proxy
  msg_ok "Started Proton Mail Bridge Services"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} IMAP Port:${CL} ${BGN}1143${CL}"
echo -e "${INFO}${YW} SMTP Port:${CL} ${BGN}1025${CL}"
echo -e "${INFO}${YW} Configure account via:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}protonmail-bridge --cli${CL}"
echo -e "${INFO}${YW} Then run 'login' to add your ProtonMail account${CL}"
