#!/usr/bin/env bash
# Iterate on a single flow in Maestro's continuous mode: it reruns the flow
# automatically every time you save the file. Ctrl-C to stop.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: scripts/debug.sh <app> <flow> [--platform <android|ios>] [--device <id>] [--no-install]

  <flow>   Flow file. An existing path, or relative to flows/<app>/.

Examples:
  scripts/debug.sh app-one smoke/app-launch.yaml
  scripts/debug.sh app-two smoke/app-launch.yaml --platform ios

Tip: pair this with 'scripts/inspect.sh studio' to find selectors live.
EOF
}

[ $# -ge 2 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
APP="$1"; FLOW="$2"; shift 2

PLATFORM_OVERRIDE=""; DEVICE=""; DO_INSTALL=1
while [ $# -gt 0 ]; do
  case "$1" in
    --platform)   PLATFORM_OVERRIDE="$2"; shift 2 ;;
    --device)     DEVICE="$2"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    *)            die "Unknown option: $1" ;;
  esac
done

load_app_config "$APP"
PLATFORM="$(resolve_platform "$PLATFORM_OVERRIDE")"

if [ -e "$FLOW" ]; then
  FLOW_PATH="$FLOW"
elif [ -e "${FLOWS_DIR}/${APP}/${FLOW}" ]; then
  FLOW_PATH="${FLOWS_DIR}/${APP}/${FLOW}"
else
  die "Flow not found: '${FLOW}' (also tried flows/${APP}/${FLOW})"
fi

case "$PLATFORM" in
  android) ensure_android_device; [ "$DO_INSTALL" -eq 1 ] && maybe_install_binary android ;;
  ios)     ensure_ios_simulator;  [ "$DO_INSTALL" -eq 1 ] && maybe_install_binary ios ;;
  *)       die "Unsupported platform: ${PLATFORM}" ;;
esac

require_cmd maestro
global=()
[ -n "$DEVICE" ] && global+=(--device "$DEVICE")

screens_dir="${REPORTS_DIR}/${APP}/screenshots/debug"
mkdir -p "$screens_dir"
SCREENSHOT_DIR="$screens_dir"; build_env_args

log "Continuous mode on ${FLOW_PATH} — edit & save to rerun, Ctrl-C to stop."
maestro ${global[@]+"${global[@]}"} test --continuous "${MAESTRO_ENV_ARGS[@]}" "$FLOW_PATH"
