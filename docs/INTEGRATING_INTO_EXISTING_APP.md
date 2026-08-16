# Integrating PIKD into an existing Flutter app

The demo repository is a runnable reference. In an existing application, add
only the PIKD packages required by the selected experience.

## 1. Choose packages

```yaml
dependencies:
  # Typed access to the PIKD backend.
  pikd_flutter_api: ^0.8.0-beta.3

  # Native AR bridge. Include only when the app presents PIKD AR.
  pikd_flutter_ar: ^0.8.0-beta.3

  # Optional prebuilt Challenges, Explore, Leaderboard, Profile, and Feed UI.
  pikd_flutter_ui: ^0.8.0-beta.3
```

Run `flutter pub get`. Use the published package versions shown above, unless
PIKD has explicitly provided a newer release for your integration.

## 2. Platform configuration

### Android

- Set `minSdk` to 24 or later and use JDK 17.
- Keep `google()` and `mavenCentral()` in dependency repositories.
- `PikdArView` does not require a PIKD-specific Android activity. Keep your
  existing host activity. If your app uses an AndroidX FragmentActivity plugin
  such as biometric authentication with `local_auth`, extend
  `FlutterFragmentActivity`:

```kotlin
package com.example.partner

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

  PIKD preserves the AndroidX lifecycle, ViewModel, and saved-state owners
  provided by `FlutterFragmentActivity`, so biometric and AR flows can coexist.
  A plain `FlutterActivity` remains supported when your app has no
  FragmentActivity-based plugin.

- Declare location permissions when using Explore.
- Configure `com.google.android.geo.API_KEY` with your Maps key.
- In this demo, copy `android/keys.properties.example` to the ignored
  `android/keys.properties` file and set `MAPS_API_KEY` before running it.
- Only keep one expensive Android platform view active during AR. Unmount a
  Google Map before mounting `PikdArView`, then recreate it after AR closes.

### iOS

- Use Flutter 3.44 or later. SwiftPM resolves PIKDARKit from the versioned GCS
  XCFramework.
- If Flutter warns that `google_maps_flutter_ios` lacks SwiftPM support, the
  warning comes from that upstream Maps plugin, not PIKD. Flutter currently
  falls back to CocoaPods for it.
- Set the deployment target to iOS 15.0 or later in the Xcode project (and in
  the Podfile too if your app still uses CocoaPods for other plugins).
- Add `NSCameraUsageDescription` and `NSLocationWhenInUseUsageDescription`.
- If using Explore, initialize Google Maps with your Maps iOS key.
- Use a physical device for ARKit verification.

## 3. Configure the PIKD API client

PIKD gives you the environment base URL and client SDK key. You provide an
opaque user reference for user-scoped modules.

```dart
import 'package:pikd_flutter_api/api.dart';

ApiClient pikdClient({
  required String baseUrl,
  required String sdkKey,
}) {
  return ApiClient(basePath: baseUrl)
    ..addDefaultHeader('x-pikd-sdk-key', sdkKey);
}
```

Do not use an email address as the user reference. Use a stable opaque identifier
from your app's identity system.

## 4. Add prebuilt modules

Wrap the application above its Navigator so every PIKD route inherits the theme:

```dart
MaterialApp(
  builder: (context, child) => PikdThemeProvider(
    theme: PikdTheme.pikdDefault(),
    child: child!,
  ),
  home: const PartnerHome(),
);
```

Create repositories using the shared client:

```dart
final client = pikdClient(baseUrl: pikdBase, sdkKey: pikdSdkKey);

PikdLeaderboardView(
  repository: PikdSdkLeaderboardRepository(
    LeaderboardApi(client),
    userRef: hostUserRef,
  ),
);

PikdProfileView(
  repository: PikdSdkProfileRepository(
    ProfileApi(client),
    userRef: hostUserRef,
  ),
);
```

Explore additionally requires an app-provided `ExploreLocationProvider` and
navigation callbacks. See `lib/geolocator_location_provider.dart` and the
Explore wiring in `lib/main.dart`.

## 5. Add AR

`PikdArView` owns its session while mounted. Do not also call
`PikdAr.startArSession()`; doing both creates a duplicate native session start.

The safe sequence is:

1. Request camera/location permission.
2. Subscribe to `PikdAr.events`.
3. Initialize `PikdAr` once for the application run.
4. Mount `PikdArView`.
5. Wait for `ArSessionStarted`, with a timeout for an already-running session.
6. Load the platform-compatible model URL.
7. Place the asset and then enable collection UI.
8. Stop/unmount AR when leaving the experience.

The complete reference is `lib/explore_ar_collect_screen.dart`. It handles
permissions, loading progress, session re-entry, pinned and nearby assets,
platform model selection, collection, and fully-collected states.

## 6. Model formats and content

- iOS uses the asset URL supplied for USDZ/Reality content.
- Android uses the asset URL supplied for GLB/glTF content.
- A null platform URL means that collectible cannot render on that platform.

## 7. Release checklist

- Use the production PIKD base URL and SDK key supplied for your tenant.
- Restrict Maps keys to the production application IDs and signing identities.
- Remove demo QA controls and test-location overrides.
- Confirm AR is hidden or gracefully unavailable on unsupported devices.
- Verify permission-denied and permanently-denied states.
- Verify collection success, already-collected, out-of-range, expired, and
  fully-collected responses.
- Test release builds on representative physical iOS and Android devices.
- Do not commit SDK keys, Maps keys, signing files, or local configuration.
