# Integrating PIKD into an existing Flutter app

For the full PIKD experience, use the turnkey facade. Your app authenticates
the user, supplies tenant configuration, presents a PIKD entry point, and
receives control again when PIKD closes. The SDK owns its Explore, AR/Collect,
Leaderboard, and Profile/Inventory screens.

## 1. Add the turnkey package

```yaml
dependencies:
  pikd_flutter_experience: ^0.8.0-beta.5
```

Run `flutter pub get`.

## 2. Complete platform setup

### Android

- Set `minSdk` to 24 or later and use JDK 17.
- Keep `google()` and `mavenCentral()` in dependency repositories.
- Add camera and coarse/fine-location permissions.
- Configure `com.google.android.geo.API_KEY` with your Android Maps key.
- Keep your existing host activity. If you use `local_auth` or another
  FragmentActivity-based plugin, extend `FlutterFragmentActivity`:

```kotlin
package com.example.app

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
```

### iOS

- Use Flutter 3.44 or later.
- Set deployment target to iOS 15.0 or later.
- Add `NSCameraUsageDescription` and `NSLocationWhenInUseUsageDescription`.
- Initialize Google Maps with your iOS Maps key if you use Explore.
- Verify AR on a physical device.

## 3. Open the PIKD experience

Build the launch configuration after your user has authenticated. `userRef`
must be a stable, opaque string; an integer client ID should use `toString()`.

```dart
import 'package:pikd_flutter_experience/pikd_flutter_experience.dart';

Future<void> openPikd(BuildContext context, int clientId) {
  return PikdFlutterExperience.open(
    context,
    configuration: PikdFlutterExperienceConfiguration(
      baseUrl: pikdBaseUrl,
      sdkKey: pikdSdkKey,
      userRef: clientId.toString(),
      // Use the language currently selected in your app.
      locale: PikdLocale.russian,
      // Use the tenant-supported API content language supplied by PIKD.
      contentLanguageRef: pikdContentLanguageRef,
      theme: appPikdTheme,
    ),
  );
}
```

The returned `Future` completes when the user closes PIKD. There is no global
initialization step, so the current user is explicit on every launch.

Your PIKD banner or launch button remains host-app UI. Localize that entry point
with your app, while keeping `PIKD` as the product name.

## 4. Apply your theme

Pass a `PikdTheme` in the launch configuration. It applies to the complete
PIKD route, including navigation, sheets, detail views, and AR controls. Map
cards use `mapSurface` and `onMapSurface` if your brand needs a specific
on-map contrast treatment.

```dart
final appPikdTheme = PikdTheme.pikdDefault().copyWith(
  colors: PikdColors.dark.copyWith(
    primary: const Color(0xFFF50F64),
    onPrimary: const Color(0xFFFFFFFF),
    activeAccent: const Color(0xFFFA91AF),
    mapSurface: const Color(0xCCFFFFFF),
    onMapSurface: const Color(0xFF2D2F32),
  ),
  typography: PikdTypography.poppins.withFontFamily('Your licensed font'),
  brandName: 'Your brand',
);
```

Only set a font family that your application has legally bundled. PIKD does not
redistribute commercial fonts; the turnkey package includes Manrope as a
fallback.

## 5. Use primitives only when you need custom composition

The facade is the recommended path for the full PIKD journey. If you need only
selected capabilities or want to build your own PIKD screens, the lower-level
packages remain available:

```yaml
dependencies:
  pikd_flutter_api: ^0.8.0-beta.5
  pikd_flutter_ui: ^0.8.0-beta.5
  pikd_flutter_ar: ^0.8.0-beta.5
```

Those packages expose the typed API client, individual PIKD widgets, and the
native AR bridge respectively. With that path, your app owns the screen
orchestration, AR lifecycle, and collection flow.

## Release checklist

- Use the production PIKD base URL and SDK key supplied for your tenant.
- Restrict Maps keys to production application IDs and signing identities.
- Verify camera and location permission-denied states.
- Verify collection success, already-collected, out-of-range, expired, and
  fully-collected responses.
- Test release builds on representative physical iOS and Android devices.
- Do not commit SDK keys, Maps keys, signing files, or local configuration.
