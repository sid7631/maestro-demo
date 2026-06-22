#!/usr/bin/env bash
# Generate (and open) an Allure HTML report from an app's JUnit results.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: scripts/report.sh <app> [--no-open] [--clean-results]

  Builds reports/<app>/allure-report from reports/<app>/allure-results.

  --no-open         Generate only; don't launch the report in a browser.
  --clean-results   Delete accumulated results first (start history fresh).

Available apps: $(list_apps | tr '\n' ' ')
EOF
}

[ $# -ge 1 ] || { usage; exit 1; }
case "$1" in -h|--help) usage; exit 0 ;; esac
APP="$1"; shift

OPEN=1; CLEAN_RESULTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-open)       OPEN=0; shift ;;
    --clean-results) CLEAN_RESULTS=1; shift ;;
    *)               die "Unknown option: $1" ;;
  esac
done

load_app_config "$APP"
require_cmd allure

results_dir="${REPORTS_DIR}/${APP}/allure-results"
report_dir="${REPORTS_DIR}/${APP}/allure-report"

[ "$CLEAN_RESULTS" -eq 1 ] && { log "Clearing ${results_dir}"; rm -rf "$results_dir"; mkdir -p "$results_dir"; }
[ -d "$results_dir" ] && [ -n "$(ls -A "$results_dir" 2>/dev/null)" ] \
  || die "No results in ${results_dir}. Run scripts/run.sh ${APP} first."

# Preserve history across runs so Allure can show trends.
if [ -d "${report_dir}/history" ]; then
  cp -r "${report_dir}/history" "${results_dir}/history"
fi

allure generate "$results_dir" -o "$report_dir" --clean
log "Report: ${report_dir}/index.html"

[ "$OPEN" -eq 1 ] && allure open "$report_dir" || true
