# PIKD Flutter SDK demo

This repository lets you evaluate PIKD's location-based discovery, prebuilt
experience modules, and native AR collection flow. PIKD sets up the backend
environment, tenant, SDK key, and test user. You supply your Google Maps keys,
normal Apple/Android application credentials, test location, and 3D assets.
PIKD configures those test assets and location in your tenant before
verification.

For copying the SDK patterns into an existing application, see
[Integrating PIKD into an existing Flutter app](docs/INTEGRATING_INTO_EXISTING_APP.md).

## What the demo includes

- Challenges, Explore, AR, Leaderboard, and Profile modules.
- A live PIKD `/sdk/v1` API connection—no fabricated fallback data.
- Google Maps discovery backed by the device's real location.
- Explore-to-AR collection and a standalone AR camera tab.
- Theme switching that demonstrates a Magnum-style rebrand.
- Correct Android surface composition and iOS/Android AR lifecycle handling.

## What you need

From PIKD:

- `PIKD_BASE`: the provisioned `/sdk/v1` base URL.
- `PIKD_SDK_KEY`: the client SDK key for the environment.
- `PIKD_USER`: an opaque test user reference.
- `PIKD_LANGUAGE_REF`: the tenant language code supplied by PIKD.

From your team:

- Flutter 3.44 or later with Dart 3.10 or later.
- Android Studio/Android SDK and JDK 17 for Android.
- Xcode and an Apple development team for iOS.
- Your Google Maps SDK keys if you use Explore.
- A physical ARKit- or ARCore-capable device for the AR flow.

Android requires API 24 or later. iOS requires version 15.0 or later.

## 1. Clone and install

```bash
git clone https://github.com/eleostechorg/pikd-demo-flutter-sdk.git
cd pikd-demo-flutter-sdk
flutter doctor
flutter pub get
```

## 2. Add the PIKD values provided to you

Create an ignored local configuration file:

```bash
cp config/pikd.example.json config/pikd.local.json
```

Edit `config/pikd.local.json`:

```json
{
  "PIKD_BASE": "https://provided-by-pikd.example/api/sdk/v1",
  "PIKD_SDK_KEY": "provided-by-pikd",
  "PIKD_USER": "your-opaque-test-user-reference",
  "PIKD_LANGUAGE_REF": "provided-by-pikd"
}
```

Do not commit `config/pikd.local.json`. `PIKD_USER` should be a stable opaque
reference from your user system, not an email address or other PII.
`PIKD_LANGUAGE_REF` is supplied by PIKD for your tenant; unsupported language
codes fail with HTTP 400 instead of silently falling back.

## 3. Run on iOS

Create or select a Google Maps iOS key enabled for Maps SDK for iOS and
restricted to the demo bundle ID `app.pikd.flutter.demo`.

Create the ignored local Xcode configuration:

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
```

Edit it with your Apple team and Maps key:

```xcconfig
DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
GOOGLE_MAPS_API_KEY = YOUR_IOS_GOOGLE_MAPS_KEY
```

Then run:

```bash
FLUTTER_DEVICE_ID=YOUR_IOS_DEVICE ./scripts/run-ios.sh
```

The script runs `flutter pub get` and launches Flutter. Flutter 3.44+ resolves
PIKDARKit from the versioned GCS XCFramework through Swift Package Manager. The
project already declares iOS 15.0, camera/location usage descriptions, and
Google Maps initialization.

## 4. Run on Android

Create or select a Google Maps Android key that is enabled for Maps SDK for
Android and restricted to the demo application ID
`app.pikd.flutter.demo` plus the signing certificate used for the build.

Create the ignored local Android configuration:

```bash
cp android/keys.properties.example android/keys.properties
```

Set your key in `android/keys.properties`:

```properties
MAPS_API_KEY=YOUR_ANDROID_GOOGLE_MAPS_KEY
```

```bash
FLUTTER_DEVICE_ID=YOUR_ANDROID_DEVICE ./scripts/run-android.sh
```

The script refuses to build if the Android Maps key is absent, then runs
dependency setup and launches Flutter with the ignored PIKD configuration.
Running `flutter run` manually with
`--dart-define-from-file=config/pikd.local.json` remains supported.

The demo already uses `FlutterFragmentActivity`, API 24, camera/location
permissions, and the renderer configuration required to show Flutter controls
over the AR camera. PIKD does not require a custom activity; use
`FlutterFragmentActivity` when your app also uses AndroidX FragmentActivity
plugins such as `local_auth` biometrics.

## 5. Verify the PIKD flow

Before this step, give PIKD your test location and platform-compatible 3D
assets. PIKD configures them in your tenant. Put the physical device at that
location or use the platform's development location simulation.

1. Open Explore and allow location access.
2. Confirm the map and nearby PIKD collectible appear.
3. Open a collectible and select Collect when in range.
4. Allow camera access.
5. Confirm the AR camera, Flutter controls, and 3D asset all render.
6. Collect the asset and confirm the success or fully-collected state.

The demo starts with a wider QA collection radius so the flow can be reviewed
indoors. Use the QA drawer to switch to the production 5 m behaviour.

## Project map

```text
lib/main.dart                         live API and prebuilt-module wiring
lib/explore_ar_collect_screen.dart   Explore/AR collection reference flow
lib/geolocator_location_provider.dart host-provided location adapter
lib/tab_bar.dart                      demo navigation shell
```

## Troubleshooting

| Symptom | Check |
|---|---|
| A PIKD package cannot be resolved | Confirm that pub.dev is reachable and run `flutter pub get` again. |
| Configuration-required screen | Confirm all four values exist in `config/pikd.local.json` and the run command uses `--dart-define-from-file`. |
| Blank or grey map | Check Maps SDK enablement, application/bundle restrictions, certificate restriction, and the platform-specific key. |
| Android runner reports missing Maps configuration | Copy `android/keys.properties.example` to `android/keys.properties` and set `MAPS_API_KEY`. |
| Map works but no collectible appears | Use the test coordinate PIKD gave you after configuring your supplied asset and location. |
| No Collect action | Move within range or use the demo QA radius control. |
| AR camera does not open | Use a physical supported device and grant camera/location permissions. |
| Camera appears without Flutter controls on Android | Confirm the app uses Flutter's default renderer configuration. PIKD does not require a custom activity; use `FlutterFragmentActivity` when another plugin, such as `local_auth`, requires it. |
| Flutter controls appear over a black Android camera | Confirm the device supports ARCore and no other expensive platform view is mounted behind AR. |
| Flutter reports a SwiftPM or PIKDARKit error | Confirm `flutter --version` is 3.44 or newer, then run the iOS script again so Flutter regenerates its SwiftPM integration. |
| Flutter warns that `google_maps_flutter_ios` lacks SwiftPM support | This is an upstream Google Maps plugin warning, not a PIKD failure. Flutter currently falls back to CocoaPods for that plugin; keep the plugin current and track its SwiftPM migration before a future Flutter release makes the warning an error. |

## Credentials and license

Never commit PIKD SDK keys, Google Maps keys, signing material, or local
configuration files. A mobile client credential is extractable from a built
application, so environment restriction, tenant scoping, monitoring, and
revocation remain important.

The PIKD SDK is proprietary software and requires a written SDK agreement with
ELEOS WORLD LTD. See [LICENSE](LICENSE).
