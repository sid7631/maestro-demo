#!/usr/bin/env bash
# Inspect the running app: launch Maestro Studio (default) or dump the view
# hierarchy. Use this to discover selectors (ids / text) for your flows.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: scripts/inspect.sh [studio|hierarchy] [--device <id>]

  studio      (default) Open Maestro Studio — interactive selector explorer.
  hierarchy   Dump the current on-screen view hierarchy to a file under
              reports/inspect/ and print its path.

Examples:
  scripts/inspect.sh
  scripts/inspect.sh hierarchy
  scripts/inspect.sh hierarchy --device emulator-5554
EOF
}

MODE="studio"
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then MODE="$1"; shift; fi
case "$MODE" in -h|--help) usage; exit 0 ;; esac

DEVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device)  DEVICE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)         die "Unknown option: $1" ;;
  esac
done

require_cmd maestro
global=()
[ -n "$DEVICE" ] && global+=(--device "$DEVICE")

case "$MODE" in
  studio)
    log "Launching Maestro Studio..."
    maestro ${global[@]+"${global[@]}"} studio
    ;;
  hierarchy)
    out_dir="${REPORTS_DIR}/inspect"
    mkdir -p "$out_dir"
    out_file="${out_dir}/hierarchy-$(date +%Y%m%d-%H%M%S).json"
    log "Capturing view hierarchy of the current screen..."
    # stdout (the hierarchy) goes to the file; Maestro's JVM warnings stay on stderr.
    maestro ${global[@]+"${global[@]}"} hierarchy > "$out_file"
    log "Saved hierarchy to:"
    printf '%s\n' "$out_file"
    ;;
  *)
    die "Unknown mode: ${MODE} (use 'studio' or 'hierarchy')"
    ;;
esac
