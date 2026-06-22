#!/usr/bin/env bash
# Shared helpers for the Maestro test scripts.
# Sourced by run.sh / debug.sh / report.sh / inspect.sh / setup.sh.
set -euo pipefail

# Resolve paths from this file's location (scripts/lib/common.sh).
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_LIB_DIR}/../.." && pwd)"

CONFIG_DIR="${REPO_ROOT}/config"
APPS_CONFIG_DIR="${CONFIG_DIR}/apps"
FLOWS_DIR="${REPO_ROOT}/flows"
REPORTS_DIR="${REPO_ROOT}/reports"
BINARIES_DIR="${REPO_ROOT}/binaries"

# IDE terminals (and non-login shells) often don't source the user's profile,
# so common install locations may be missing from PATH. Add them defensively.
for _p in "${HOME}/.maestro/bin" /opt/homebrew/bin /usr/local/bin "${ANDROID_HOME:-${HOME}/Library/Android/sdk}/platform-tools"; do
  [ -d "${_p}" ] || continue
  case ":${PATH}:" in *":${_p}:"*) ;; *) PATH="${_p}:${PATH}" ;; esac
done
export PATH
unset _p

log()  { printf '\033[0;34m[maestro]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[0;33m[warn]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: '$1'. Run scripts/setup.sh first."
}

# Resolve a usable `node` binary. nvm-managed node isn't on PATH in
# non-interactive shells, so fall back to brew locations and the newest nvm
# install. Prints the path on success; returns 1 if none found.
resolve_node() {
  if command -v node >/dev/null 2>&1; then command -v node; return 0; fi
  local c
  for c in /opt/homebrew/bin/node /usr/local/bin/node; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  c="$(ls -1 "${HOME}/.nvm/versions/node"/*/bin/node 2>/dev/null | sort -V | tail -1)"
  [ -n "$c" ] && [ -x "$c" ] && { echo "$c"; return 0; }
  return 1
}

# Print the available app keys (filenames in config/apps without .env).
list_apps() {
  [ -d "${APPS_CONFIG_DIR}" ] || return 0
  for f in "${APPS_CONFIG_DIR}"/*.env; do
    [ -e "$f" ] || continue
    basename "$f" .env
  done | sort
}

# load_app_config <app-key>: sources global defaults then the per-app .env.
# Exports APP_ID, APP_NAME, PLATFORM, *_APP_BINARY, etc. into the environment.
load_app_config() {
  local app="$1"
  local app_file="${APPS_CONFIG_DIR}/${app}.env"
  [ -f "${app_file}" ] || die "Unknown app '${app}'. Available: $(list_apps | tr '\n' ' ')"

  if [ -f "${CONFIG_DIR}/global.env" ]; then
    set -a; . "${CONFIG_DIR}/global.env"; set +a
  fi
  set -a; . "${app_file}"; set +a

  : "${APP_ID:?APP_ID must be set in ${app_file}}"
  APP_NAME="${app}"
  export APP_NAME
}

# Resolve the platform: explicit override > app config > global default > android.
resolve_platform() {
  local override="${1:-}"
  echo "${override:-${PLATFORM:-${DEFAULT_PLATFORM:-android}}}"
}

ensure_android_device() {
  require_cmd adb
  local n
  n="$(adb devices | grep -cw 'device' || true)"
  [ "${n}" -ge 1 ] || die "No Android device/emulator detected. Start an emulator (AVD Manager) or connect a device with USB debugging on."
}

ensure_ios_simulator() {
  require_cmd xcrun
  xcrun simctl list devices booted 2>/dev/null | grep -q 'Booted' \
    || die "No booted iOS simulator. Open Simulator.app or run: xcrun simctl boot <udid>"
}

# maybe_install_binary <platform>: install the configured build if it exists,
# otherwise assume the app is already installed (launch-only).
maybe_install_binary() {
  local platform="$1"
  case "${platform}" in
    android)
      if [ -n "${ANDROID_APP_BINARY:-}" ] && [ -f "${REPO_ROOT}/${ANDROID_APP_BINARY}" ]; then
        log "Installing ${ANDROID_APP_BINARY} ..."
        adb install -r "${REPO_ROOT}/${ANDROID_APP_BINARY}"
      else
        warn "No Android binary for '${APP_NAME}'; assuming '${APP_ID}' is already installed."
      fi ;;
    ios)
      if [ -n "${IOS_APP_BINARY:-}" ] && [ -e "${REPO_ROOT}/${IOS_APP_BINARY}" ]; then
        log "Installing ${IOS_APP_BINARY} ..."
        xcrun simctl install booted "${REPO_ROOT}/${IOS_APP_BINARY}"
      else
        warn "No iOS binary for '${APP_NAME}'; assuming '${APP_ID}' is already installed."
      fi ;;
  esac
}
