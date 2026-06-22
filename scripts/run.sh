#!/usr/bin/env bash
# Run a Maestro flow / suite for a given app and emit JUnit results for Allure.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: scripts/run.sh <app> [target] [options] [-- <extra maestro args>]

  <app>      App key from config/apps/<app>.env
             Available: $(list_apps | tr '\n' ' ')
  [target]   Flow file or directory. Resolved as: an existing path, or relative
             to flows/<app>/. Default: the whole flows/<app> suite.

Options:
  --platform <android|ios>   Override platform (default from app config)
  --tags <a,b>               Only run flows with these tags
  --exclude-tags <a,b>       Skip flows with these tags
  --device <id>              Target a specific device/emulator/simulator
  --no-install               Skip installing the app binary
  -h, --help

Examples:
  scripts/run.sh app-one
  scripts/run.sh app-one smoke
  scripts/run.sh app-one smoke/app-launch.yaml --tags smoke
  scripts/run.sh app-two --platform ios --device "iPhone 15"
EOF
}

PLATFORM_OVERRIDE=""; INCLUDE_TAGS=""; EXCLUDE_TAGS=""
DEVICE=""; DO_INSTALL=1; EXTRA=()

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
APP="$1"; shift

TARGET=""
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then TARGET="$1"; shift; fi

while [ $# -gt 0 ]; do
  case "$1" in
    --platform)     PLATFORM_OVERRIDE="$2"; shift 2 ;;
    --tags)         INCLUDE_TAGS="$2"; shift 2 ;;
    --exclude-tags) EXCLUDE_TAGS="$2"; shift 2 ;;
    --device)       DEVICE="$2"; shift 2 ;;
    --no-install)   DO_INSTALL=0; shift ;;
    --)             shift; EXTRA=("$@"); break ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "Unknown option: $1" ;;
  esac
done

load_app_config "$APP"
PLATFORM="$(resolve_platform "$PLATFORM_OVERRIDE")"

# Resolve target flow path.
if [ -z "$TARGET" ]; then
  FLOW_PATH="${FLOWS_DIR}/${APP}"
elif [ -e "$TARGET" ]; then
  FLOW_PATH="$TARGET"
elif [ -e "${FLOWS_DIR}/${APP}/${TARGET}" ]; then
  FLOW_PATH="${FLOWS_DIR}/${APP}/${TARGET}"
else
  die "Target not found: '${TARGET}' (also tried flows/${APP}/${TARGET})"
fi

# Device readiness + app install.
case "$PLATFORM" in
  android) ensure_android_device; [ "$DO_INSTALL" -eq 1 ] && maybe_install_binary android ;;
  ios)     ensure_ios_simulator;  [ "$DO_INSTALL" -eq 1 ] && maybe_install_binary ios ;;
  *)       die "Unsupported platform: ${PLATFORM}" ;;
esac

require_cmd maestro
ts="$(date +%Y%m%d-%H%M%S)"
results_dir="${REPORTS_DIR}/${APP}/allure-results"
debug_dir="${REPORTS_DIR}/${APP}/debug/${ts}"
screens_dir="${REPORTS_DIR}/${APP}/screenshots/${ts}"
mkdir -p "$results_dir" "$debug_dir" "$screens_dir"
# JUnit goes to the debug dir; allure-results holds only native results+attachments.
junit_out="${debug_dir}/junit.xml"

global=()
[ -n "$DEVICE" ] && global+=(--device "$DEVICE")

SCREENSHOT_DIR="$screens_dir"; build_env_args
args=(test "${MAESTRO_ENV_ARGS[@]}")
[ -n "$INCLUDE_TAGS" ] && args+=(--include-tags "$INCLUDE_TAGS")
[ -n "$EXCLUDE_TAGS" ] && args+=(--exclude-tags "$EXCLUDE_TAGS")
args+=(--format junit --output "$junit_out" --debug-output "$debug_dir" "$FLOW_PATH")
[ ${#EXTRA[@]} -gt 0 ] && args+=("${EXTRA[@]}")

log "Running: app=${APP} platform=${PLATFORM} flows=${FLOW_PATH}"
status=0
maestro ${global[@]+"${global[@]}"} "${args[@]}" || status=$?

# Convert Maestro's JUnit + this run's screenshots into native Allure results
# (so screenshots show up in the report). Remove any legacy junit-*.xml left in
# allure-results by older runs, which would otherwise show up without images.
if [ ! -s "$junit_out" ]; then
  warn "No JUnit produced by Maestro (did the run fail before any flow ran?). allure-results not updated."
elif NODE_BIN="$(resolve_node)"; then
  rm -f "${results_dir}"/junit-*.xml
  "$NODE_BIN" "${_LIB_DIR}/allure_from_maestro.js" \
    --junit "$junit_out" --screenshots "$screens_dir" \
    --results "$results_dir" --app "$APP" --flow "$FLOW_PATH" \
    || warn "Allure conversion failed; report will still build from prior results."
else
  err "Node.js not found — cannot build Allure results. Install it (brew install node) or run scripts/setup.sh, then re-run."
fi

log "JUnit results : ${junit_out}"
log "Screenshots   : ${screens_dir}"
log "Debug output  : ${debug_dir}"
log "Build report  : scripts/report.sh ${APP}"
exit "$status"
