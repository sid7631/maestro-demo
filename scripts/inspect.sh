#!/usr/bin/env bash
# Inspect the running app: launch Maestro Studio (default) or dump the view
# hierarchy. Use this to discover selectors (ids / text) for your flows.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: scripts/inspect.sh [studio|hierarchy] [--device <id>]

  studio      (default) Open Maestro Studio — interactive selector explorer.
  hierarchy   Print the current on-screen view hierarchy to stdout.

Examples:
  scripts/inspect.sh
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
  studio)    log "Launching Maestro Studio..."; maestro ${global[@]+"${global[@]}"} studio ;;
  hierarchy) maestro ${global[@]+"${global[@]}"} hierarchy ;;
  *)         die "Unknown mode: ${MODE} (use 'studio' or 'hierarchy')" ;;
esac
