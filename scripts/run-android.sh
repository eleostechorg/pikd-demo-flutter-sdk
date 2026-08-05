#!/usr/bin/env bash

# Public Android demo runner. Flutter packages and the native SDK resolve from
# their public registries; local credentials come only from ignored config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=demo-common.sh
source "$SCRIPT_DIR/demo-common.sh"

if [ -z "${MAPS_API_KEY:-}" ]; then
  echo "MAPS_API_KEY is not exported; Gradle must find it in a user-level Gradle property." >&2
fi

prepare_flutter

if [ -n "${FLUTTER_DEVICE_ID:-}" ]; then
  flutter run -d "$FLUTTER_DEVICE_ID" \
    --dart-define-from-file="$PIKD_CONFIG_FILE"
else
  flutter run --dart-define-from-file="$PIKD_CONFIG_FILE"
fi
