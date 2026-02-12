#!/usr/bin/env bash
# Install/uninstall Input Leap systemd service and timer for automatic
# connection management.
#
# Configures Input Leap client to auto-connect to server on boot and
# periodically reconnect if connection drops. Supports both system-wide
# and user-level installations, interactive and non-interactive modes.
#
# Usage: sudo ./install.sh [OPTIONS]
# Run with --help for full usage information.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly SYSTEM_UNIT_DIR="/etc/systemd/system"

readonly UNIT_FILES=(
  "inputleap.service"
  "inputleap-reconnect.service"
  "inputleap-reconnect.timer"
)

# Prints usage information
#
# Arguments:
#   None
#
# Returns:
#   Usage text to stdout
#
# Exit codes:
#   0 - Always succeeds
print_usage() {
  cat <<'EOF'
Usage: sudo ./install.sh [OPTIONS]

Install or uninstall Input Leap client systemd services.

Options:
  --user USERNAME     Username to run Input Leap as
  --server ADDRESS    Server address (IP, hostname, or host:port)
  --system            Install system-wide (default)
  --user-level        Install as user-level service
  --uninstall         Remove installed services
  --dry-run           Print rendered unit files without installing
  --help              Show this help message

Interactive mode (no flags):
  sudo ./install.sh

Non-interactive examples:
  sudo ./install.sh --user john --server 10.0.0.1 --system
  sudo ./install.sh --user john --server myhost:24800 --user-level
  sudo ./install.sh --user john --uninstall --system
  sudo ./install.sh --user john --server 10.0.0.1 --dry-run
EOF
}

# Validates that running with root privileges
#
# Arguments:
#   None
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Running as root
#   1 - Not running as root
check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: Must run with sudo" >&2
    return 1
  fi
}

# Resolves the path to the input-leapc binary
#
# Arguments:
#   None
#
# Returns:
#   Absolute path to input-leapc
#
# Exit codes:
#   0 - Binary found
#   1 - Binary not found
resolve_binary() {
  local binary_path
  binary_path="$(command -v input-leapc 2>/dev/null)" || {
    echo "Error: input-leapc not found in PATH" >&2
    return 1
  }
  echo "${binary_path}"
}

# Gets home directory for a user via getent
#
# Arguments:
#   $1 - username: System username
#
# Returns:
#   Home directory path
#
# Exit codes:
#   0 - Success
#   1 - User not found or missing parameter
get_home_dir() {
  local username="$1"

  [[ -z "${username}" ]] && {
    echo "Error: Username cannot be empty" >&2
    return 1
  }

  local home_dir
  home_dir="$(getent passwd "${username}" | cut -d: -f6)" || {
    echo "Error: Could not resolve home for: ${username}" >&2
    return 1
  }

  [[ -z "${home_dir}" ]] && {
    echo "Error: Empty home directory for: ${username}" >&2
    return 1
  }

  echo "${home_dir}"
}

# Prompts user for username
#
# Arguments:
#   None
#
# Returns:
#   Username string
#
# Exit codes:
#   0 - Always succeeds
get_username() {
  local username_input
  read -rp "Enter username to run Input Leap as: " username_input
  echo "${username_input}"
}

# Prompts user for server address
#
# Arguments:
#   None
#
# Returns:
#   Server address string
#
# Exit codes:
#   0 - Always succeeds
get_server_address() {
  local address_input
  read -rp "Enter server address (IP, hostname, or host:port): " \
    address_input
  echo "${address_input}"
}

# Validates individual IP octets are in range 0-255
#
# Arguments:
#   $1 - ip_address: Dotted-quad IP string
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - All octets valid
#   1 - Octet out of range
validate_ip_octets() {
  local ip_address="$1"
  local -a octets
  IFS='.' read -ra octets <<<"${ip_address}"

  for octet in "${octets[@]}"; do
    if [[ "${octet}" -lt 0 || "${octet}" -gt 255 ]]; then
      echo "Error: IP octet out of range: ${octet}" >&2
      return 1
    fi
  done
}

# Validates server address format (IP, hostname, or host:port)
#
# Arguments:
#   $1 - address: Server address to validate
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Valid address
#   1 - Empty or invalid address
validate_server_address() {
  local address="$1"

  [[ -z "${address}" ]] && {
    echo "Error: Server address cannot be empty" >&2
    return 1
  }

  local host="${address}"
  local port=""

  if [[ "${address}" == *:* ]]; then
    host="${address%:*}"
    port="${address##*:}"

    if [[ -z "${port}" || ! "${port}" =~ ^[0-9]+$ ]]; then
      echo "Error: Invalid port in address: ${address}" >&2
      return 1
    fi
    if [[ "${port}" -lt 1 || "${port}" -gt 65535 ]]; then
      echo "Error: Port out of range: ${port}" >&2
      return 1
    fi
  fi

  local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
  local hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$'

  if [[ "${host}" =~ ${ip_regex} ]]; then
    validate_ip_octets "${host}"
  elif [[ "${host}" =~ ${hostname_regex} ]]; then
    return 0
  else
    echo "Error: Invalid server address: ${address}" >&2
    return 1
  fi
}

# Validates username exists on system
#
# Arguments:
#   $1 - username: System username to validate
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - User exists
#   1 - Empty username or user does not exist
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

# Prompts user for installation type and normalizes input
#
# Arguments:
#   None
#
# Returns:
#   "system" or "user"
#
# Exit codes:
#   0 - Valid input received
#   1 - Invalid input
get_install_type() {
  local type_input
  read -rp "Install as system-wide service? (y/n, default: y): " \
    type_input
  type_input="${type_input:-y}"

  case "${type_input}" in
    y | Y | yes | Yes) echo "system" ;;
    n | N | no | No) echo "user" ;;
    *)
      echo "Error: Invalid input: ${type_input}" >&2
      return 1
      ;;
  esac
}

# Checks for existing unit files and warns before overwrite
#
# Arguments:
#   $1 - install_type: "system" or "user"
#   $2 - username: System username (used for user-level path)
#
# Returns:
#   Warning message if files exist
#
# Exit codes:
#   0 - Always succeeds (warning only)
detect_existing_install() {
  local install_type="$1"
  local username="$2"
  local dest_dir

  if [[ "${install_type}" == "system" ]]; then
    dest_dir="${SYSTEM_UNIT_DIR}"
  else
    local home_dir
    home_dir="$(get_home_dir "${username}")"
    dest_dir="${home_dir}/.config/systemd/user"
  fi

  local found=false
  for unit_file in "${UNIT_FILES[@]}"; do
    if [[ -f "${dest_dir}/${unit_file}" ]]; then
      found=true
      break
    fi
  done

  if [[ "${found}" == "true" ]]; then
    echo "Warning: Existing install found in ${dest_dir}" >&2
    echo "Existing files will be overwritten." >&2
  fi
}

# Renders a template unit file with all placeholder substitutions
#
# Arguments:
#   $1 - template_path: Path to the template unit file
#   $2 - binary_path: Absolute path to input-leapc
#   $3 - server_address: Server address string
#   $4 - username: System username (only used for system service)
#
# Returns:
#   Rendered unit file content
#
# Exit codes:
#   0 - Success
#   1 - Template file not found
render_unit_file() {
  local template_path="$1"
  local binary_path="$2"
  local server_address="${3:-}"
  local username="${4:-}"

  [[ -f "${template_path}" ]] || {
    echo "Error: Template not found: ${template_path}" >&2
    return 1
  }

  local content
  content="$(<"${template_path}")"
  content="${content//BINARY_PATH/${binary_path}}"
  content="${content//SERVER_ADDRESS/${server_address}}"

  if [[ -n "${username}" ]]; then
    content="${content//YOUR_USERNAME/${username}}"
  fi

  echo "${content}"
}

# Installs service files for system-wide setup
#
# Arguments:
#   $1 - source_dir: Directory containing template unit files
#   $2 - username: System username
#   $3 - server_address: Server address string
#   $4 - binary_path: Absolute path to input-leapc
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
install_system_wide() {
  local source_dir="$1"
  local username="$2"
  local server_address="$3"
  local binary_path="$4"

  echo "Installing to ${SYSTEM_UNIT_DIR}"

  render_unit_file \
    "${source_dir}/inputleap.service" \
    "${binary_path}" "${server_address}" "${username}" |
    install -m 644 /dev/stdin \
      "${SYSTEM_UNIT_DIR}/inputleap.service"

  for unit_file in "inputleap-reconnect.service" \
    "inputleap-reconnect.timer"; do
    render_unit_file \
      "${source_dir}/${unit_file}" "${binary_path}" |
      install -m 644 /dev/stdin \
        "${SYSTEM_UNIT_DIR}/${unit_file}"
  done
}

# Installs service files for user-level setup
#
# Arguments:
#   $1 - source_dir: Directory containing template unit files
#   $2 - username: System username
#   $3 - server_address: Server address string
#   $4 - binary_path: Absolute path to input-leapc
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
install_user_level() {
  local source_dir="$1"
  local username="$2"
  local server_address="$3"
  local binary_path="$4"
  local home_dir
  home_dir="$(get_home_dir "${username}")"
  local dest_dir="${home_dir}/.config/systemd/user"

  mkdir -p "${dest_dir}"
  echo "Installing to ${dest_dir}"

  render_unit_file \
    "${source_dir}/inputleap.service" \
    "${binary_path}" "${server_address}" |
    install -m 644 /dev/stdin \
      "${dest_dir}/inputleap.service"

  for unit_file in "inputleap-reconnect.service" \
    "inputleap-reconnect.timer"; do
    render_unit_file \
      "${source_dir}/${unit_file}" "${binary_path}" |
      install -m 644 /dev/stdin \
        "${dest_dir}/${unit_file}"
  done

  chown -R "${username}:${username}" "${dest_dir}"
}

# Enables and starts systemd services (system-wide)
#
# Arguments:
#   None
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
start_system_services() {
  systemctl daemon-reload
  systemctl enable inputleap.service inputleap-reconnect.timer
  systemctl start inputleap.service inputleap-reconnect.timer
  systemctl status inputleap.service
  echo "View logs: journalctl -u inputleap -f"
}

# Enables and starts systemd services (user-level)
#
# Passes XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS so that
# systemctl --user works when invoked via sudo.
#
# Arguments:
#   $1 - username: System username
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
#   1 - Could not determine user uid
start_user_services() {
  local username="$1"
  local user_uid
  user_uid="$(id -u "${username}")"
  local runtime_dir="/run/user/${user_uid}"
  local dbus_address="unix:path=${runtime_dir}/bus"

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user daemon-reload

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user enable \
    inputleap.service inputleap-reconnect.timer

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user start \
    inputleap.service inputleap-reconnect.timer

  echo "View logs: journalctl --user-unit inputleap -f"
}

# Stops, disables, and removes system-wide unit files
#
# Arguments:
#   None
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
uninstall_system_wide() {
  echo "Uninstalling system-wide services"

  systemctl stop inputleap.service inputleap-reconnect.timer \
    2>/dev/null || true
  systemctl disable inputleap.service inputleap-reconnect.timer \
    2>/dev/null || true

  for unit_file in "${UNIT_FILES[@]}"; do
    rm -f "${SYSTEM_UNIT_DIR}/${unit_file}"
  done

  systemctl daemon-reload
  echo "System-wide services removed"
}

# Stops, disables, and removes user-level unit files
#
# Arguments:
#   $1 - username: System username
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
uninstall_user_level() {
  local username="$1"
  local user_uid
  user_uid="$(id -u "${username}")"
  local runtime_dir="/run/user/${user_uid}"
  local dbus_address="unix:path=${runtime_dir}/bus"
  local home_dir
  home_dir="$(get_home_dir "${username}")"
  local dest_dir="${home_dir}/.config/systemd/user"

  echo "Uninstalling user-level services for ${username}"

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user stop \
    inputleap.service inputleap-reconnect.timer \
    2>/dev/null || true

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user disable \
    inputleap.service inputleap-reconnect.timer \
    2>/dev/null || true

  for unit_file in "${UNIT_FILES[@]}"; do
    rm -f "${dest_dir}/${unit_file}"
  done

  sudo -u "${username}" \
    env "XDG_RUNTIME_DIR=${runtime_dir}" \
    "DBUS_SESSION_BUS_ADDRESS=${dbus_address}" \
    systemctl --user daemon-reload

  echo "User-level services removed for ${username}"
}

# Parses command-line arguments into global config variables
#
# Arguments:
#   $@ - Command-line arguments
#
# Returns:
#   Sets global variables: ARG_USER, ARG_SERVER, ARG_INSTALL_TYPE,
#   ARG_UNINSTALL, ARG_DRY_RUN, ARG_HELP
#
# Exit codes:
#   0 - Success
#   1 - Invalid arguments
parse_args() {
  ARG_USER=""
  ARG_SERVER=""
  ARG_INSTALL_TYPE=""
  ARG_UNINSTALL=false
  ARG_DRY_RUN=false
  ARG_HELP=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user)
        [[ $# -ge 2 ]] || {
          echo "Error: --user requires a value" >&2
          return 1
        }
        ARG_USER="$2"
        shift 2
        ;;
      --server)
        [[ $# -ge 2 ]] || {
          echo "Error: --server requires a value" >&2
          return 1
        }
        ARG_SERVER="$2"
        shift 2
        ;;
      --system)
        ARG_INSTALL_TYPE="system"
        shift
        ;;
      --user-level)
        ARG_INSTALL_TYPE="user"
        shift
        ;;
      --uninstall)
        ARG_UNINSTALL=true
        shift
        ;;
      --dry-run)
        ARG_DRY_RUN=true
        shift
        ;;
      --help)
        ARG_HELP=true
        shift
        ;;
      *)
        echo "Error: Unknown option: $1" >&2
        print_usage >&2
        return 1
        ;;
    esac
  done
}

# Prints rendered unit files to stdout for review
#
# Arguments:
#   $1 - source_dir: Directory containing template unit files
#   $2 - binary_path: Absolute path to input-leapc
#   $3 - server_address: Server address string
#   $4 - username: System username
#   $5 - install_type: "system" or "user"
#
# Returns:
#   Rendered unit file contents
#
# Exit codes:
#   0 - Success
run_dry_run() {
  local source_dir="$1"
  local binary_path="$2"
  local server_address="$3"
  local username="$4"
  local install_type="$5"

  for unit_file in "${UNIT_FILES[@]}"; do
    echo "--- ${unit_file} ---"
    if [[ "${unit_file}" == "inputleap.service" &&
      "${install_type}" == "system" ]]; then
      render_unit_file \
        "${source_dir}/${unit_file}" \
        "${binary_path}" "${server_address}" "${username}"
    elif [[ "${unit_file}" == "inputleap.service" ]]; then
      render_unit_file \
        "${source_dir}/${unit_file}" \
        "${binary_path}" "${server_address}"
    else
      render_unit_file \
        "${source_dir}/${unit_file}" "${binary_path}"
    fi
    echo ""
  done
}

# Main installation routine
#
# Arguments:
#   $@ - Command-line arguments (passed to parse_args)
#
# Returns:
#   Nothing
#
# Exit codes:
#   0 - Success
#   1 - Validation or installation failure
main() {
  parse_args "$@"

  if [[ "${ARG_HELP}" == "true" ]]; then
    print_usage
    return 0
  fi

  check_root

  local username="${ARG_USER}"
  local server_address="${ARG_SERVER}"
  local install_type="${ARG_INSTALL_TYPE}"
  local has_flags=false

  if [[ -n "${username}" || -n "${server_address}" ||
    -n "${install_type}" ||
    "${ARG_UNINSTALL}" == "true" ||
    "${ARG_DRY_RUN}" == "true" ]]; then
    has_flags=true
  fi

  if [[ "${has_flags}" == "false" ]]; then
    username="$(get_username)"
    validate_username "${username}"
    server_address="$(get_server_address)"
    validate_server_address "${server_address}"
    install_type="$(get_install_type)"

    local binary_path
    binary_path="$(resolve_binary)"
    local source_dir="${SCRIPT_DIR}/${install_type}"

    detect_existing_install "${install_type}" "${username}"

    if [[ "${install_type}" == "system" ]]; then
      install_system_wide \
        "${source_dir}" "${username}" \
        "${server_address}" "${binary_path}"
      start_system_services
    else
      install_user_level \
        "${source_dir}" "${username}" \
        "${server_address}" "${binary_path}"
      start_user_services "${username}"
    fi
    echo "Input Leap installed successfully"
    return 0
  fi

  if [[ -z "${username}" ]]; then
    echo "Error: --user is required" >&2
    return 1
  fi
  validate_username "${username}"

  if [[ -z "${install_type}" ]]; then
    install_type="system"
  fi

  if [[ "${ARG_UNINSTALL}" == "true" ]]; then
    if [[ "${install_type}" == "system" ]]; then
      uninstall_system_wide
    else
      uninstall_user_level "${username}"
    fi
    return 0
  fi

  if [[ -z "${server_address}" ]]; then
    echo "Error: --server is required" >&2
    return 1
  fi
  validate_server_address "${server_address}"

  local binary_path
  binary_path="$(resolve_binary)"
  local source_dir="${SCRIPT_DIR}/${install_type}"

  if [[ "${ARG_DRY_RUN}" == "true" ]]; then
    run_dry_run \
      "${source_dir}" "${binary_path}" \
      "${server_address}" "${username}" "${install_type}"
    return 0
  fi

  detect_existing_install "${install_type}" "${username}"

  if [[ "${install_type}" == "system" ]]; then
    install_system_wide \
      "${source_dir}" "${username}" \
      "${server_address}" "${binary_path}"
    start_system_services
  else
    install_user_level \
      "${source_dir}" "${username}" \
      "${server_address}" "${binary_path}"
    start_user_services "${username}"
  fi
  echo "Input Leap installed successfully"
}

main "$@"
