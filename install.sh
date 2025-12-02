#!/usr/bin/env bash
# Install InputLeap systemd service and timer for automatic connection
#
# Configures InputLeap client to auto-connect to server on boot and
# periodically reconnect if connection drops. Supports both system-wide
# and user-level installations.
#
# Usage: sudo ./install.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Validates that running with root privileges
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Must run with sudo" >&2
    return 1
  fi
}

# Prompts user for username with default fallback
get_username() {
  local username_input
  read -rp "Enter username to run InputLeap as: " \
    username_input
  echo "${username_input}"
}

# Prompts user for server IP with default fallback
get_server_ip() {
  local ip_input
  read -rp "Enter server IP address: " ip_input
  echo "${ip_input}"
}

# Validates IP address format
validate_ip_address() {
  local ip="$1"

  [[ -z "${ip}" ]] && {
    echo "Error: IP address cannot be empty" >&2
    return 1
  }

  local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  [[ "${ip}" =~ ${ip_regex} ]] || {
    echo "Error: Invalid IP address format: ${ip}" >&2
    return 1
  }
}

# Validates username exists on system
validate_username() {
  local username="$1"

  [[ -z "${username}" ]] && {
    echo "Error: Username cannot be empty" >&2
    return 1
  }

  id "${username}" &>/dev/null || {
    echo "Error: User does not exist: ${username}" >&2
    return 1
  }
}

# Prompts user for installation type (system-wide or user-level)
get_install_type() {
  local type_input
  read -rp "Install as system-wide service? (y/n, default: y): " \
    type_input
  echo "${type_input:-y}"
}

# Installs service files for system-wide setup
install_system_wide() {
  local source_dir="$1"
  local username="$2"
  local server_ip="$3"
  local dest_dir="/etc/systemd/system"

  echo "Installing to ${dest_dir}"

  sed "s|192.0.2.1|${server_ip}|g" \
    "${source_dir}/inputleap.service" |
    sed "s|User=YOUR_USERNAME|User=${username}|g" \
    >"${dest_dir}/inputleap.service"

  cp "${source_dir}/inputleap-reconnect.service" \
    "${dest_dir}/"
  cp "${source_dir}/inputleap-reconnect.timer" \
    "${dest_dir}/"
}

# Installs service files for user-level setup
install_user_level() {
  local source_dir="$1"
  local username="$2"
  local server_ip="$3"
  local dest_dir="/home/${username}/.config/systemd/user"

  mkdir -p "${dest_dir}"
  echo "Installing to ${dest_dir}"

  sed "s|192.0.2.1|${server_ip}|g" \
    "${source_dir}/inputleap.service" \
    >"${dest_dir}/inputleap.service"

  cp "${source_dir}/inputleap-reconnect.service" \
    "${dest_dir}/"
  cp "${source_dir}/inputleap-reconnect.timer" \
    "${dest_dir}/"

  chown -R "${username}:${username}" "${dest_dir}"
}

# Enables and starts systemd services (system-wide)
start_system_services() {
  systemctl daemon-reload
  systemctl enable inputleap.service inputleap-reconnect.timer
  systemctl start inputleap.service inputleap-reconnect.timer

  systemctl status inputleap.service
  echo "View logs: journalctl -u inputleap -f"
}

# Enables and starts systemd services (user-level)
start_user_services() {
  local username="$1"

  sudo -u "${username}" systemctl --user daemon-reload
  sudo -u "${username}" systemctl --user enable \
    inputleap.service inputleap-reconnect.timer
  sudo -u "${username}" systemctl --user start \
    inputleap.service inputleap-reconnect.timer

  echo "View logs: journalctl --user-unit inputleap -f"
}

# Main installation routine
main() {
  check_root

  local username
  username="$(get_username)"
  validate_username "${username}"

  local server_ip
  server_ip="$(get_server_ip)"
  validate_ip_address "${server_ip}"

  local install_type
  install_type="$(get_install_type)"

  local source_dir
  if [[ "${install_type}" == "y" ]]; then
    source_dir="${SCRIPT_DIR}/system"
    install_system_wide "${source_dir}" "${username}" "${server_ip}"
    start_system_services
  else
    source_dir="${SCRIPT_DIR}/user"
    install_user_level "${source_dir}" "${username}" "${server_ip}"
    start_user_services "${username}"
  fi

  echo "InputLeap installed successfully"
}

main "$@"
