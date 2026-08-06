#!/usr/bin/env bash

# Public Android demo runner. Flutter packages and the native SDK resolve from
# their public registries; local credentials come only from ignored config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=demo-common.sh
source "$SCRIPT_DIR/demo-common.sh"

ANDROID_MAPS_PROPERTIES="$PIKD_DEMO_ROOT/android/keys.properties"
[ -f "$ANDROID_MAPS_PROPERTIES" ] || {
  echo "Missing Android Maps configuration: $ANDROID_MAPS_PROPERTIES" >&2
  echo "Copy android/keys.properties.example to android/keys.properties and set MAPS_API_KEY." >&2
  exit 1
}
grep -Eq '^[[:space:]]*MAPS_API_KEY[[:space:]]*=[[:space:]]*[^[:space:]#]+' "$ANDROID_MAPS_PROPERTIES" || {
  echo "Android Maps configuration has no MAPS_API_KEY value: $ANDROID_MAPS_PROPERTIES" >&2
  exit 1
}
if grep -Eq '^[[:space:]]*MAPS_API_KEY[[:space:]]*=[[:space:]]*YOUR_ANDROID_GOOGLE_MAPS_KEY[[:space:]]*$' "$ANDROID_MAPS_PROPERTIES"; then
  echo "Android Maps configuration still contains the example placeholder: $ANDROID_MAPS_PROPERTIES" >&2
  exit 1
fi

prepare_flutter

if [ -n "${FLUTTER_DEVICE_ID:-}" ]; then
  flutter run -d "$FLUTTER_DEVICE_ID" \
    --dart-define-from-file="$PIKD_CONFIG_FILE"
else
  flutter run --dart-define-from-file="$PIKD_CONFIG_FILE"
fi
