# PIKD Flutter experience demo

This runnable app shows Magnum's intended host integration: your app presents
a PIKD entry point, then `pikd_flutter_magnum_experience` owns the complete
PIKD journey — single-challenge Explore, Mechanics, AR collection, Leaderboard,
and My Collections.

Use it to validate your environment before adding PIKD to an existing Flutter
application. For the integration steps, see
[Integrating PIKD into an existing Flutter app](docs/INTEGRATING_INTO_EXISTING_APP.md).

## What you need

PIKD provides these five values for your tenant:

- `PIKD_BASE` — the `/sdk/v1` base URL.
- `PIKD_SDK_KEY` — the tenant SDK key.
- `PIKD_USER` — a stable, opaque test-user reference.
- `PIKD_UI_LOCALE` — the PIKD interface language: `ru` or `kk`.
- `PIKD_CONTENT_LANGUAGE_REF` — the tenant-supported language for returned
  collectible and challenge content, supplied by PIKD.

You provide:

- Flutter 3.44 or later and Dart 3.10 or later.
- A physical ARKit- or ARCore-capable device for AR verification.
- Your Google Maps SDK keys for Explore.
- Normal Apple and Android application signing configuration.

Android requires API 24 or later; iOS requires 15.0 or later.

## 1. Clone and configure PIKD

```bash
git clone https://github.com/eleostechorg/pikd-demo-flutter-sdk.git
cd pikd-demo-flutter-sdk
flutter pub get

cp config/pikd.example.json config/pikd.local.json
```

Fill `config/pikd.local.json` with the five PIKD values. It is ignored by Git;
do not commit it. `PIKD_USER` should be an opaque ID from your user system, not
an email address or other PII.

Magnum's facade resolves the tenant's one active challenge at launch and uses
the backend challenge name throughout the experience. A new active challenge
therefore requires no app rebuild and no challenge metadata in this file.

The demo launch card follows `PIKD_UI_LOCALE` too. In your app, replace that
card with your own localized PIKD entry point; keep `PIKD` as the product name.

## 2. Run on iOS

Enable Maps SDK for iOS for a Google Maps key and restrict it to the demo bundle
ID, `app.pikd.flutter.demo`.

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
```

Edit `ios/Flutter/Local.xcconfig`:

```xcconfig
DEVELOPMENT_TEAM = YOUR_APPLE_TEAM_ID
GOOGLE_MAPS_API_KEY = YOUR_IOS_GOOGLE_MAPS_KEY
```

Connect a physical iPhone, find its identifier with `flutter devices`, then run:

```bash
FLUTTER_DEVICE_ID=YOUR_IOS_DEVICE ./scripts/run-ios.sh
```

Flutter 3.44+ resolves the PIKDARKit binary through Swift Package Manager. The
demo already declares iOS 15, camera/location usage descriptions, and Google
Maps initialization.

## 3. Run on Android

Enable Maps SDK for Android for a Google Maps key and restrict it to the demo
application ID, `app.pikd.flutter.demo`, and the signing certificate you use.

```bash
cp android/keys.properties.example android/keys.properties
```

Set the key in `android/keys.properties`:

```properties
MAPS_API_KEY=YOUR_ANDROID_GOOGLE_MAPS_KEY
```

Connect a physical Android device, find its identifier with `flutter devices`,
then run:

```bash
FLUTTER_DEVICE_ID=YOUR_ANDROID_DEVICE ./scripts/run-android.sh
```

The demo uses `FlutterFragmentActivity`, API 24, and the camera/location
permissions required by AR. You can retain `FlutterFragmentActivity` in an app
that also uses AndroidX FragmentActivity plugins such as `local_auth`. When AR
opens, the SDK automatically checks Google Play Services for AR and offers its
standard install/update flow where required.

## 4. Verify the PIKD flow

1. Select **Open PIKD**.
2. In Explore, allow location access and confirm the map loads.
3. Confirm Explore opens with Magnum's one active challenge already selected;
   there is no challenge picker or clear button.
4. Select an available collectible and choose **Collect** when you are in range.
5. Allow camera access, then confirm the AR camera, 3D asset, and controls
   render.
6. Collect the asset and confirm the returned result state.
7. Open **Mechanics**, **Leaderboard**, and **My Collections**. Mechanics must
   open the active challenge directly with no comments; Leaderboard must not show
   raw user references or avatar slots; My Collections must show owned items
   directly without profile details or tabs.

The SDK’s collection radius is 5 metres. PIKD enables the tenant content used
for your evaluation; if nothing appears on the map, contact PIKD with your test
location rather than changing application code.

## Troubleshooting

| Symptom | Check |
|---|---|
| A PIKD package cannot be resolved | Confirm pub.dev is reachable and run `flutter pub get` again. |
| Configuration-required screen | Confirm all five values exist in `config/pikd.local.json`. |
| Blank or grey map | Check Maps SDK enablement and your platform-specific key restrictions. |
| Android reports missing Maps configuration | Create `android/keys.properties` and set `MAPS_API_KEY`. |
| Map loads but no collectible appears | Confirm PIKD has enabled content near your test location. |
| No Collect action | Move within the configured 5-metre collection radius. |
| AR camera does not open | Use a supported physical device and grant camera/location permissions. |
| SwiftPM or PIKDARKit error | Confirm Flutter 3.44+ and rerun the iOS script. |
| `google_maps_flutter_ios` SwiftPM warning | This is an upstream Maps-plugin warning. Flutter currently falls back to CocoaPods for that plugin. |

## Credentials and licence

Never commit PIKD SDK keys, Google Maps keys, signing material, or local
configuration files. Mobile-client credentials are extractable from a built app,
so tenant scoping, monitoring, and revocation remain important.

The PIKD SDK is proprietary software and requires a written SDK agreement with
ELEOS WORLD LTD. See [LICENSE](LICENSE).
