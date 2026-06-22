#!/usr/bin/env bash
# One-time setup checks/installs for running Maestro on macOS.
# Safe to re-run; it only installs what's missing.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

has() { command -v "$1" >/dev/null 2>&1; }

log "Checking Maestro prerequisites on macOS..."

if ! has brew; then
  warn "Homebrew not found. Install from https://brew.sh, then re-run this script."
fi

# JDK 11+ (required by Maestro).
if ! /usr/libexec/java_home >/dev/null 2>&1; then
  if has brew; then log "Installing Temurin JDK..."; brew install --cask temurin
  else warn "No JDK found. Install a JDK 11+ (e.g. Temurin)."; fi
else
  log "JDK present: $(/usr/libexec/java_home)"
fi

# Maestro CLI.
if ! has maestro; then
  log "Installing Maestro CLI..."
  curl -fsSL "https://get.maestro.mobile.dev" | bash
  warn "Add \"\$HOME/.maestro/bin\" to your PATH (see the installer's output), then restart your shell."
else
  log "Maestro present: $(maestro --version 2>/dev/null || echo '?')"
fi

# Allure (reporting).
if ! has allure; then
  if has brew; then log "Installing Allure..."; brew install allure
  else warn "Allure not found. Install with: brew install allure"; fi
else
  log "Allure present."
fi

# Node.js (used to build Allure results with screenshots).
if ! resolve_node >/dev/null 2>&1; then
  if has brew; then log "Installing Node.js..."; brew install node
  else warn "Node.js not found. Install with: brew install node"; fi
else
  log "Node present: $(resolve_node)"
fi

# Android (primary target).
if ! has adb; then
  warn "adb not found (Android). Install Android Studio + SDK platform-tools:"
  warn "    brew install --cask android-studio"
  warn "  Then: open Android Studio > SDK Manager (install an SDK) and AVD Manager (create an emulator),"
  warn "  and add \"\$HOME/Library/Android/sdk/platform-tools\" to your PATH."
else
  log "adb present."
fi

# iOS (optional / secondary).
if ! has xcrun; then
  warn "Xcode command line tools not found (only needed for iOS): xcode-select --install"
else
  log "Xcode tools present (iOS supported)."
fi

log "Done. See README.md for usage."
