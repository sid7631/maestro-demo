#!/usr/bin/env bash
# Manage the Android input method (IME) used for text entry during tests.
#
# Why this exists: Maestro types text on Android via `adb shell input text`,
# which only reliably handles plain ASCII and silently drops many symbols. The
# result is that `inputText` "does nothing" (the field focuses, keyboard shows,
# but no text lands) — especially for passwords/emails with special characters.
# The fix is ADBKeyboard, a tiny IME that receives text over broadcast intents;
# Maestro uses it automatically when it's the active keyboard.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ADB_IME="com.android.adbkeyboard/.AdbIME"
ADB_PKG="com.android.adbkeyboard"
APK_URL="https://github.com/senzhk/ADBKeyBoard/raw/master/ADBKeyboard.apk"
STATE_DIR="${REPORTS_DIR}/state"
PREV_IME_FILE="${STATE_DIR}/previous-ime.txt"
APK_CACHE="${STATE_DIR}/ADBKeyboard.apk"

usage() {
  cat >&2 <<EOF
Usage: scripts/keyboard.sh <command> [--device <id>]

  use-adb    Install (if needed), enable, and activate ADBKeyboard so Maestro
             can enter text reliably. Saves your current keyboard to restore later.
  restore    Switch back to the keyboard that was active before 'use-adb'.
  status     Print the currently active input method.

Examples:
  scripts/keyboard.sh use-adb
  scripts/keyboard.sh restore
EOF
}

CMD="${1:-status}"
case "$CMD" in -h|--help) usage; exit 0 ;; esac
shift || true

DEVICE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

ensure_android_device
ADB=(adb)
[ -n "$DEVICE" ] && ADB+=(-s "$DEVICE")
adbx() { "${ADB[@]}" "$@"; }

current_ime() { adbx shell settings get secure default_input_method 2>/dev/null | tr -d '\r'; }

case "$CMD" in
  use-adb)
    cur="$(current_ime)"
    if [ "$cur" != "$ADB_IME" ] && [ -n "$cur" ] && [ "$cur" != "null" ]; then
      mkdir -p "$STATE_DIR"
      printf '%s\n' "$cur" > "$PREV_IME_FILE"
      log "Saved current keyboard for later restore: ${cur}"
    fi

    if adbx shell pm list packages 2>/dev/null | tr -d '\r' | grep -q "package:${ADB_PKG}"; then
      log "ADBKeyboard already installed."
    else
      log "Installing ADBKeyboard..."
      if [ ! -f "$APK_CACHE" ]; then
        require_cmd curl
        mkdir -p "$STATE_DIR"
        curl -fL -o "$APK_CACHE" "$APK_URL"
      fi
      adbx install -r "$APK_CACHE"
    fi

    adbx shell ime enable "$ADB_IME" >/dev/null
    adbx shell ime set "$ADB_IME" >/dev/null
    log "ADBKeyboard is now active — Maestro inputText will work."
    log "Restore your normal keyboard later with: scripts/keyboard.sh restore"
    ;;

  restore)
    prev=""
    [ -f "$PREV_IME_FILE" ] && prev="$(tr -d '\r' < "$PREV_IME_FILE")"
    if [ -n "$prev" ] && [ "$prev" != "null" ]; then
      adbx shell ime set "$prev" >/dev/null
      log "Restored keyboard: ${prev}"
    else
      warn "No saved keyboard found. Pick one of the installed IMEs and set it, or use Settings:"
      adbx shell ime list -s 2>/dev/null | tr -d '\r'
      warn "  e.g. adb shell ime set <id>   (or Settings > General management > Keyboard list and default)"
    fi
    ;;

  status)
    log "Active input method:"
    current_ime
    ;;

  *)
    die "Unknown command: ${CMD} (use 'use-adb', 'restore', or 'status')"
    ;;
esac
