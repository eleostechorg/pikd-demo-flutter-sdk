#!/usr/bin/env bash

# Public iOS demo runner. Flutter packages and PIKDARKit resolve from their
# public registries; local credentials come only from ignored config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=demo-common.sh
source "$SCRIPT_DIR/demo-common.sh"

LOCAL_XCCONFIG="$PIKD_DEMO_ROOT/ios/Flutter/Local.xcconfig"
[ -f "$LOCAL_XCCONFIG" ] || {
  echo "Missing iOS local settings: $LOCAL_XCCONFIG" >&2
  echo "Copy ios/Flutter/Local.xcconfig.example to Local.xcconfig and set the Apple team and Maps key." >&2
  exit 1
}

require_command pod
prepare_flutter
# Refresh CocoaPods specs so a newly published PIKDARKit release resolves on a
# first run even when the local CDN cache predates it.
(cd "$PIKD_DEMO_ROOT/ios" && pod install --repo-update)

if [ -n "${FLUTTER_DEVICE_ID:-}" ]; then
  flutter run -d "$FLUTTER_DEVICE_ID" \
    --dart-define-from-file="$PIKD_CONFIG_FILE"
else
  flutter run --dart-define-from-file="$PIKD_CONFIG_FILE"
fi
