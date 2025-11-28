#!/usr/bin/env bash
# openconnect-toggle
# Licensed under the GNU GPL v3 or later.

set -eu

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

CONFIG_DIR="${HOME}/Library/Application Support/openconnect-toggle"
CONFIG_FILE="${CONFIG_DIR}/openconnect-toggle.cfg"

LOG_DIR="${HOME}/Library/Logs"
LOG_FILE="${LOG_DIR}/openconnect-toggle.log"

PID_FILE="${HOME}/.openconnect.pid"
PROTOCOL="anyconnect"   # can be changed later if needed

mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# ---------- config helpers ----------

initial_config_setup() {
  if [[ -f "$CONFIG_FILE" ]]; then
    return
  fi

  echo "=== openconnect-toggle: initial setup ==="
  printf "Enter VPN server hostname (e.g. vpn.example.com): "
  read -r server
  if [[ -z "$server" ]]; then
    server="vpn.example.com"
  fi

  printf "Enter path to CA certificate file [ca.crt]: "
  read -r cafile_src
  if [[ -z "$cafile_src" ]]; then
    cafile_src="ca.crt"
  fi

  # expand ~
  if [[ "$cafile_src" == ~* ]]; then
    cafile_src="${cafile_src/#\~/$HOME}"
  fi

  # if not absolute and not ~, treat as relative to the script directory
  if [[ "$cafile_src" != /* && "$cafile_src" != ~* ]]; then
    cafile_src="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/$cafile_src"
  fi

  if [[ ! -f "$cafile_src" ]]; then
    echo "Error: CA file not found at '$cafile_src'." >&2
    echo "Please make sure the file exists and run openconnect-toggle again." >&2
    exit 1
  fi

  local cafile_name
  cafile_name="$(basename "$cafile_src")"
  cp "$cafile_src" "${CONFIG_DIR}/${cafile_name}"

  cat > "$CONFIG_FILE" <<EOF
SERVER=$server
CA_FILE=$cafile_name
TOUCHID_DENIED=0
TOUCHID_ADDED=0
SWIFTBAR_INSTALLED=0
SWIFTBAR_DENIED=0
SWIFTBAR_PLUGIN_PATH=
CURRENT_USER=
# USER_<username>=1 marks known users
EOF

  echo "Config created: $CONFIG_FILE"
  echo "CA copied to: ${CONFIG_DIR}/${cafile_name}"
}

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # Temporarily disable 'exit on error' to avoid breaking on old malformed lines
    set +e
    # shellcheck disable=SC1090
    . "$CONFIG_FILE" 2>/dev/null || true
    set -e
  fi
  CA_FILE="${CA_FILE:-ca.crt}"
}

save_config_var() {
  local key="$1"
  local value="$2"
  touch "$CONFIG_FILE"

  # escape single quotes in value for safe single-quoting
  local escaped
  escaped=$(printf "%s" "$value" | sed "s/'/'\\\\''/g")

  if grep -q "^${key}=" "$CONFIG_FILE" 2>/dev/null; then
    sed -i '' "s|^${key}=.*|${key}='${escaped}'|" "$CONFIG_FILE"
  else
    echo "${key}='${escaped}'" >> "$CONFIG_FILE"
  fi
}

user_is_known() {
  local username="$1"
  local var="USER_${username}"
  eval "[[ -n \"\${$var:-}\" ]]"
}

mark_user_known() {
  local username="$1"
  save_config_var "USER_${username}" 1
}

list_users() {
  if [[ -f "$CONFIG_FILE" ]]; then
    grep '^USER_' "$CONFIG_FILE" 2>/dev/null | sed 's/^USER_//; s/=.*//'
  fi
}

has_any_user() {
  list_users | grep . >/dev/null 2>&1
}

# ---------- Touch ID helper (interactive only) ----------

ensure_touchid_for_sudo() {
  local pam_file="/etc/pam.d/sudo"

  if grep -q "pam_tid.so" "$pam_file" 2>/dev/null; then
    # pam_tid.so already present, we did not add it
    return
  fi

  if [[ "${TOUCHID_DENIED:-0}" == "1" ]]; then
    return
  fi

  echo "Touch ID can be enabled for sudo (confirm sudo with fingerprint)."
  printf "Enable Touch ID for sudo now? [y/N]: "
  read -r ans

  case "$ans" in
    [yY]|[yY][eE][sS])
      echo "Updating $pam_file..."
      if sudo sed -i '' '1s/^/auth       sufficient     pam_tid.so\n/' "$pam_file"; then
        echo "Touch ID for sudo enabled."
        save_config_var "TOUCHID_DENIED" 0
        save_config_var "TOUCHID_ADDED" 1
      else
        echo "Failed to modify $pam_file." >&2
      fi
      ;;
    *)
      save_config_var "TOUCHID_DENIED" 1
      echo "Keeping sudo without Touch ID. You can reset this by removing $CONFIG_FILE."
      ;;
  esac
}

# ---------- SwiftBar helpers (interactive only) ----------

swiftbar_app_installed() {
  [[ -d "/Applications/SwiftBar.app" || -d "${HOME}/Applications/SwiftBar.app" ]]
}

swiftbar_running() {
  pgrep -x "SwiftBar" >/dev/null 2>&1
}

install_swiftbar_via_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is not installed; cannot install SwiftBar automatically." >&2
    return 1
  fi
  if brew list --cask swiftbar >/dev/null 2>&1; then
    return 0
  fi
  echo "Installing SwiftBar via Homebrew..."
  if ! brew install --cask swiftbar; then
    echo "Failed to install SwiftBar via Homebrew." >&2
    return 1
  fi
  return 0
}

ensure_swiftbar_install_for_cli() {
  case "$SCRIPT_PATH" in
    *SwiftBar/plugins/*|*SwiftBar/Plugins/*)
      save_config_var "SWIFTBAR_INSTALLED" 1
      save_config_var "SWIFTBAR_PLUGIN_PATH" "$SCRIPT_PATH"
      return
      ;;
  esac

  if [[ "${SWIFTBAR_INSTALLED:-0}" == "1" || "${SWIFTBAR_DENIED:-0}" == "1" ]]; then
    return
  fi

  echo "SwiftBar integration can show VPN status in the macOS menu bar."
  printf "Set up SwiftBar integration now? [y/N]: "
  read -r ans

  case "$ans" in
    [yY]|[yY][eE][sS])
      if ! swiftbar_app_installed; then
        echo "SwiftBar is not installed."
        printf "Install SwiftBar via Homebrew now? [y/N]: "
        read -r ans2
        case "$ans2" in
          [yY]|[yY][eE][sS])
            if ! install_swiftbar_via_brew; then
              save_config_var "SWIFTBAR_DENIED" 1
              echo "SwiftBar installation failed; aborting integration." >&2
              exit 1
            fi
            ;;
          *)
            save_config_var "SWIFTBAR_DENIED" 1
            echo "SwiftBar integration cancelled." >&2
            exit 1
            ;;
        esac
      fi

      local default_plugins_dir="$HOME/Library/Application Support/SwiftBar/plugins"
      printf "SwiftBar plugins directory [%s]: " "$default_plugins_dir"
      read -r plugins_dir
      if [[ -z "$plugins_dir" ]]; then
        plugins_dir="$default_plugins_dir"
      fi

      mkdir -p "$plugins_dir"

      local plugin_script="${plugins_dir}/openconnect-toggle.1m.sh"
      cp "$SCRIPT_PATH" "$plugin_script"
      chmod +x "$plugin_script"

      save_config_var "SWIFTBAR_INSTALLED" 1
      save_config_var "SWIFTBAR_PLUGIN_PATH" "$plugin_script"

      echo "SwiftBar plugin installed:"
      echo "  $plugin_script"
      echo "Config and CA are stored in:"
      echo "  $CONFIG_DIR"

      if swiftbar_running; then
        echo "SwiftBar is already running. Use 'Reload Plugins' from the SwiftBar menu if needed."
      else
        echo "Starting SwiftBar..."
        if open -a "SwiftBar"; then
          echo "SwiftBar started. The plugin should appear in the menu bar shortly."
        else
          echo "Failed to start SwiftBar automatically. Please launch it manually." >&2
        fi
      fi
      ;;
    *)
      save_config_var "SWIFTBAR_DENIED" 1
      echo "SwiftBar integration skipped. You can reset this by removing $CONFIG_FILE."
      ;;
  esac
}

# ---------- user / keychain helpers ----------

ensure_user_credentials() {
  local username="$1"
  local service="openconnect:${SERVER}"

  if ! security find-generic-password -a "${username}" -s "${service}" -w >/dev/null 2>&1; then
    echo "No password found in Keychain for user '${username}' and service '${service}'."
    printf "Enter VPN password for %s: " "$username"
    stty -echo
    read -r password
    stty echo
    echo
    security add-generic-password -a "${username}" -s "${service}" -w "${password}"
    echo "Password stored in Keychain."
  fi

  mark_user_known "$username"
}

ensure_some_user_interactive() {
  if has_any_user; then
    return
  fi

  echo "No VPN users are configured yet."
  printf "Enter VPN username: "
  read -r username
  if [[ -z "$username" ]]; then
    echo "Username cannot be empty." >&2
    exit 1
  fi

  ensure_user_credentials "$username"
}

add_user_interactive() {
  initial_config_setup
  load_config

  echo "Adding a new VPN user."
  printf "Enter new VPN username: "
  read -r username
  if [[ -z "$username" ]]; then
    echo "Username cannot be empty." >&2
    exit 1
  fi

  if user_is_known "$username"; then
    echo "User '$username' is already known in config."
  else
    ensure_user_credentials "$username"
    echo "User '$username' added."
  fi
}

# ---------- status helpers ----------

is_running() {
  [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE" 2>/dev/null)" >/dev/null 2>&1
}

# returns "iface ip" or empty string
get_vpn_iface_and_ip() {
  ifconfig 2>/dev/null | awk '
    /^[ut]tun[0-9]:/ {
      iface=$1
      sub(":", "", iface)
    }
    iface ~ /^(utun|tun)/ && $1=="inet" {
      print iface, $2
      exit
    }
  ' || true
}

compute_status() {
  local info
  info="$(get_vpn_iface_and_ip)"
  STATUS_IFACE=""
  STATUS_IP=""
  if [[ -n "$info" ]]; then
    STATUS_IFACE="${info%% *}"
    STATUS_IP="${info#* }"
  fi
  if is_running; then
    STATUS_CONNECTED=1
  else
    STATUS_CONNECTED=0
  fi
}

cli_print_status_and_exit() {
  compute_status
  local cur_user="${CURRENT_USER:-}"
  local server="${SERVER:-}"

  if (( STATUS_CONNECTED )); then
    if [[ -n "$cur_user" && -n "$server" ]]; then
      echo "VPN connected for ${cur_user}@${server}."
    elif [[ -n "$server" ]]; then
      echo "VPN connected to ${server}."
    else
      echo "VPN connected."
    fi
    status=0
  else
    echo "VPN disconnected."
    status=1
  fi

  if [[ -n "${STATUS_IFACE}" ]]; then
    echo "Interface: ${STATUS_IFACE}"
  else
    echo "Interface: none"
  fi

  if [[ -n "${STATUS_IP}" ]]; then
    echo "VPN IP: ${STATUS_IP}"
  else
    echo "VPN IP: none"
  fi

  exit "$status"
}

swiftbar_mode() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❔"
    echo "---"
    echo "openconnect-toggle is not configured."
    echo "Run 'openconnect-toggle' in Terminal to set it up."
    return
  fi

  load_config

  local users
  users="$(list_users || true)"

  compute_status
  local icon
  if (( STATUS_CONNECTED )); then
    icon="🔒"
  else
    icon="🔓"
  fi

  echo "$icon"
  echo "---"
  if (( STATUS_CONNECTED )); then
    echo "Status: connected"
  else
    echo "Status: disconnected"
  fi

  if [[ -n "${STATUS_IFACE}" ]]; then
    echo "Interface: ${STATUS_IFACE}"
  else
    echo "Interface: none"
  fi

  if [[ -n "${STATUS_IP}" ]]; then
    echo "VPN IP: ${STATUS_IP}"
  else
    echo "VPN IP: none"
  fi

  echo "---"
  if [[ -n "$users" ]]; then
    local u
    while IFS= read -r u; do
      [[ -z "$u" ]] && continue
      echo "Toggle VPN (${u}) | bash=\"$SCRIPT_PATH\" param1=\"${u}\" terminal=true"
    done <<< "$users"
  else
    echo "No users configured."
  fi
  echo "Add user... | bash=\"$SCRIPT_PATH\" param1=\"adduser\" terminal=true"
}

# ---------- reset & uninstall ----------

reset_all() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Nothing to reset: config not found at $CONFIG_FILE"
    exit 0
  fi

  load_config
  local server="${SERVER:-}"
  local users
  users="$(list_users || true)"
  local service=""

  if [[ -n "$server" ]]; then
    service="openconnect:${server}"
  fi

  if [[ -n "$users" && -n "$service" ]]; then
    while IFS= read -r u; do
      [[ -z "$u" ]] && continue
      security delete-generic-password -a "$u" -s "$service" >/dev/null 2>&1 || true
      echo "Removed Keychain item for user '$u' (service='$service')."
    done <<< "$users"
  fi

  rm -rf "$CONFIG_DIR"
  echo "Configuration directory removed: $CONFIG_DIR"
  exit 0
}

uninstall_all() {
  if [[ $INTERACTIVE -eq 0 ]]; then
    echo "-uninstall must be run in an interactive terminal." >&2
    exit 1
  fi

  local server=""
  local touchid_added="0"
  local plugin_path=""
  local users=""
  local service=""

  if [[ -f "$CONFIG_FILE" ]]; then
    load_config
    server="${SERVER:-}"
    touchid_added="${TOUCHID_ADDED:-0}"
    plugin_path="${SWIFTBAR_PLUGIN_PATH:-}"
    users="$(list_users || true)"
    if [[ -n "$server" ]]; then
      service="openconnect:${server}"
    fi
  else
    echo "Config not found at $CONFIG_FILE; proceeding with partial uninstall."
  fi

  echo "This will remove openconnect-toggle configuration and Keychain entries for configured users."
  printf "Continue? [y/N]: "
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS]) ;;
    *)
      echo "Uninstall cancelled."
      exit 0
      ;;
  esac

  if [[ -n "$users" && -n "$service" ]]; then
    while IFS= read -r u; do
      [[ -z "$u" ]] && continue
      security delete-generic-password -a "$u" -s "$service" >/dev/null 2>&1 || true
      echo "Removed Keychain item for user '$u' (service='$service')."
    done <<< "$users"
  fi

  if [[ -d "$CONFIG_DIR" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "Configuration directory removed: $CONFIG_DIR"
  fi

  if [[ -n "$plugin_path" && -f "$plugin_path" ]]; then
    printf "Remove SwiftBar plugin at '%s'? [y/N]: " "$plugin_path"
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        rm -f "$plugin_path"
        echo "SwiftBar plugin removed."
        ;;
    esac
  fi

  if [[ -f "$LOG_FILE" ]]; then
    printf "Remove log file '%s'? [y/N]: " "$LOG_FILE"
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        rm -f "$LOG_FILE"
        echo "Log file removed."
        ;;
    esac
  fi

  if swiftbar_app_installed; then
    printf "Uninstall SwiftBar (via Homebrew if possible)? [y/N]: "
    read -r ans
    case "$ans" in
      [yY]|[yY][eE][sS])
        if command -v brew >/dev/null 2>&1; then
          if ! brew uninstall --cask swiftbar; then
            echo "Failed to uninstall SwiftBar via Homebrew. You may remove the app manually." >&2
          else
            echo "SwiftBar uninstalled via Homebrew."
          fi
        else
          echo "Homebrew not available. Please remove SwiftBar manually from /Applications or ~/Applications."
        fi
        ;;
    esac
  fi

  if [[ "$touchid_added" == "1" ]]; then
    local pam_file="/etc/pam.d/sudo"
    if grep -q "pam_tid.so" "$pam_file" 2>/dev/null; then
      printf "Remove Touch ID integration from %s that was added by this script? [y/N]: " "$pam_file"
      read -r ans
      case "$ans" in
        [yY]|[yY][eE][sS])
          if sudo sed -i '' '/auth[[:space:]]\+sufficient[[:space:]]\+pam_tid.so/d' "$pam_file"; then
            echo "Touch ID integration removed from sudo PAM config."
          else
            echo "Failed to modify $pam_file. You may need to edit it manually." >&2
          fi
          ;;
      esac
    fi
  fi

  echo "Uninstall complete. Script file and original certificate (if any) were not removed."
  exit 0
}

# ---------- main ----------

INTERACTIVE=0
if [[ -t 0 && -t 1 ]]; then
  INTERACTIVE=1
fi

# special single-argument modes: -reset, -uninstall
if [[ $# -eq 1 ]]; then
  case "$1" in
    -reset)
      reset_all
      ;;
    -uninstall)
      uninstall_all
      ;;
  esac
fi

# no arguments
if [[ $# -eq 0 ]]; then
  if (( INTERACTIVE )); then
    initial_config_setup
    load_config
    SERVER="${SERVER:?SERVER must be set in ${CONFIG_FILE}}"
    CA_FILE="${CA_FILE:-ca.crt}"

    ensure_some_user_interactive
    ensure_touchid_for_sudo
    ensure_swiftbar_install_for_cli

    cli_print_status_and_exit
  else
    swiftbar_mode
    exit 0
  fi
fi

# argument present
ARG1="$1"

# "adduser" mode
if [[ "$ARG1" == "adduser" ]]; then
  if (( INTERACTIVE )); then
    add_user_interactive
    exit 0
  else
    echo "adduser must be run in an interactive terminal." >&2
    exit 1
  fi
fi

USERNAME="$ARG1"

initial_config_setup
load_config
SERVER="${SERVER:?SERVER must be set in ${CONFIG_FILE}}"
CA_FILE="${CA_FILE:-ca.crt}"

CA_PATH="${CONFIG_DIR}/${CA_FILE}"
if [[ ! -f "$CA_PATH" ]]; then
  echo "Error: CA certificate not found: $CA_PATH" >&2
  exit 1
fi

command -v openconnect >/dev/null 2>&1 || {
  echo "Error: openconnect not installed. Install with: brew install openconnect" >&2
  exit 1
}

KEYCHAIN_SERVICE="openconnect:${SERVER}"

if (( INTERACTIVE )); then
  ensure_touchid_for_sudo
  ensure_swiftbar_install_for_cli
fi

ensure_user_credentials "$USERNAME"

CURRENT_USER="${CURRENT_USER:-}"
running=0
if is_running; then
  running=1
fi

if (( running )); then
  PID="$(cat "$PID_FILE" 2>/dev/null || true)"

  if [[ -n "${PID}" ]]; then
    sudo kill -INT "$PID" 2>/dev/null || true
  else
    sudo killall openconnect 2>/dev/null || true
  fi

  sleep 2
  if is_running; then
    echo "Error: failed to disconnect VPN." >&2
    exit 1
  fi

  save_config_var "CURRENT_USER" ""

  if [[ "$CURRENT_USER" == "$USERNAME" ]]; then
    echo "VPN disconnected."
    exit 0
  fi
fi

# connect as USERNAME
if ! PASSWD="$(security find-generic-password -a "${USERNAME}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)"; then
  echo "Error: password not found in Keychain for account='${USERNAME}', service='${KEYCHAIN_SERVICE}'." >&2
  echo "You can fix this by deleting $CONFIG_FILE and running the script again for re-setup." >&2
  exit 1
fi

if ! printf '%s\n' "${PASSWD}" | sudo openconnect \
      --protocol="${PROTOCOL}" \
      --user="${USERNAME}" \
      --passwd-on-stdin \
      --background \
      --pid-file="${PID_FILE}" \
      --cafile="${CA_PATH}" \
      "${SERVER}" \
      2>>"$LOG_FILE"
then
  echo "Error: openconnect failed to start. See log: $LOG_FILE" >&2
  exit 1
fi

sleep 3
if ! is_running; then
  echo "Error: VPN did not stay connected. See log: $LOG_FILE" >&2
  exit 1
fi

save_config_var "CURRENT_USER" "$USERNAME"
cli_print_status_and_exit

