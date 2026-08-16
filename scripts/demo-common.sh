#!/usr/bin/env bash

# Shared, secret-free setup for the public Android and iOS demo runners.

PIKD_DEMO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIKD_CONFIG_FILE="${PIKD_CONFIG_FILE:-$PIKD_DEMO_ROOT/config/pikd.local.json}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_swiftpm_flutter() {
  require_command flutter
  local flutter_version
  flutter_version="$(flutter --version | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1)"
  local major minor
  IFS=. read -r major minor _ <<< "$flutter_version"
  if [ -z "$major" ] || [ -z "$minor" ] || (( major < 3 || (major == 3 && minor < 44) )); then
    echo "iOS SwiftPM support requires Flutter 3.44 or later; found ${flutter_version:-unknown}." >&2
    exit 1
  fi
}

require_demo_config() {
  if [ ! -f "$PIKD_CONFIG_FILE" ]; then
    echo "Missing local PIKD configuration: $PIKD_CONFIG_FILE" >&2
    echo "Copy config/pikd.example.json to config/pikd.local.json and fill in the values provided by PIKD." >&2
    exit 1
  fi

  PIKD_CONFIG_FILE="$(cd "$(dirname "$PIKD_CONFIG_FILE")" && pwd)/$(basename "$PIKD_CONFIG_FILE")"
  if grep -Eq 'provided-by-pikd|your-opaque-test-user-reference' "$PIKD_CONFIG_FILE"; then
    echo "PIKD configuration still contains example placeholders: $PIKD_CONFIG_FILE" >&2
    exit 1
  fi
}

prepare_flutter() {
  require_command flutter
  require_demo_config
  cd "$PIKD_DEMO_ROOT"
  if [ "${PIKD_CLEAN:-0}" = "1" ]; then
    flutter clean
  fi
  flutter pub get
}
