import 'package:flutter/foundation.dart'
    show TargetPlatform, debugPrint, defaultTargetPlatform, visibleForTesting;
import 'package:geolocator/geolocator.dart';
import 'package:pikd_flutter_ui/pikd_flutter_ui.dart';

/// Raised when the device position is genuinely unknown — no fix, no last-known
/// position, no permission or no location service.
///
/// This exists so callers stop conflating it with "there is nothing nearby". An
/// empty collectible list makes a claim about the world; a missing position makes
/// one about the device, and the AR screen renders them very differently: the
/// former is a legitimate live camera with an empty HUD, the latter needs to tell
/// the user to check their location settings.
class LocationUnavailableException implements Exception {
  const LocationUnavailableException();

  @override
  String toString() => 'Device location is unavailable';
}

/// Real device-GPS location provider for the Explore map, backed by `geolocator`
/// (the same recipe the AR binding uses). This lives in the EXAMPLE, not the
/// core package — `pikd_flutter_ui` takes no location dependency; the host supplies one.
///
/// The fix resolution matters more than it looks. A bare
/// `Geolocator.getCurrentPosition()` defaults to [LocationAccuracy.best] with no
/// time limit, so on a fresh install the first call waits for a GPS-grade lock —
/// which indoors can take tens of seconds or never arrive. Every caller treats a
/// null location as "nothing nearby", so the first visit to the AR tab showed a
/// live camera with no assets and no chrome, and only worked after visiting
/// Explore, whose position *stream* had warmed the platform provider.
///
/// This mirrors what the React Native app does (`src/lib/utils/geolocation.ts`):
/// coarse accuracy on Android, a hard time limit, and a short process-wide cache
/// so a second screen never pays for a fresh fix. The last-known fallback is an
/// addition — `geolocator` exposes it and it is strictly better than nothing.
class GeolocatorExploreLocationProvider extends ExploreLocationProvider {
  /// Shared across instances: callers construct a provider per screen, but the
  /// device only has one position. Without this the AR tab cannot benefit from a
  /// fix the map already paid for.
  static ExploreLatLng? _cached;
  static DateTime? _cachedAt;
  static Future<ExploreLatLng?>? _inFlight;

  /// Long enough that moving between tabs reuses one fix, short enough that a
  /// walking user is not navigating against a stale position. Matches RN.
  static const Duration _cacheTtl = Duration(seconds: 10);

  /// A fix must arrive in bounded time or the caller gets the best thing
  /// available. Without a limit `getCurrentPosition` waits indefinitely.
  static const Duration _fixTimeout = Duration(seconds: 10);

  /// Android takes the fused provider's answer rather than waiting for a GPS
  /// lock — near-instant, and ~100 m is far inside the radius these queries use.
  /// iOS is cheap to ask precisely, and matches RN's `enableHighAccuracy` split.
  static LocationAccuracy get _accuracy =>
      defaultTargetPlatform == TargetPlatform.iOS
          ? LocationAccuracy.high
          : LocationAccuracy.medium;

  /// Seeds the shared cache from the position stream, so an active map keeps the
  /// AR tab's first call instant.
  static void _remember(ExploreLatLng pos) {
    _cached = pos;
    _cachedAt = DateTime.now();
  }

  /// Clears the shared position cache.
  ///
  /// The cache is deliberately process-wide — a device has one location, and
  /// sharing it is what stops each screen paying for its own fix. The cost is
  /// that it outlives any single test, so a test that resolves a position would
  /// leak into the next one and make the suite order-dependent. Call this in
  /// `setUp` to keep tests isolated.
  @visibleForTesting
  static void resetCache() {
    _cached = null;
    _cachedAt = null;
    _inFlight = null;
  }

  /// Ages the cached fix past its TTL while keeping the position.
  ///
  /// Lets a test reach the expired-cache fallback without sleeping for the TTL or
  /// making the clock injectable — the position is retained, only its timestamp
  /// moves, which is exactly the state a user returning after a few minutes hits.
  @visibleForTesting
  static void expireCacheForTest() {
    if (_cachedAt != null) _cachedAt = _cachedAt!.subtract(_cacheTtl * 2);
  }

  LocationPermissionStatus _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.blocked;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.requestable;
    }
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return LocationPermissionStatus.requestable;
    }
    return _map(await Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      _map(await Geolocator.requestPermission());

  @override
  Future<ExploreLatLng?> getCurrentLocation() async {
    final cachedAt = _cachedAt;
    if (_cached != null && cachedAt != null && DateTime.now().difference(cachedAt) < _cacheTtl) {
      return _cached;
    }
    // Two screens opening at once must not start two fixes; the second awaits
    // the first. Concurrent requests were previously independent, so the AR tab
    // and the map could each pay for a cold fix.
    return _inFlight ??= _resolve()..whenComplete(() => _inFlight = null);
  }

  Future<ExploreLatLng?> _resolve() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: _accuracy, timeLimit: _fixTimeout),
      );
      final here = ExploreLatLng(pos.latitude, pos.longitude);
      _remember(here);
      return here;
    } catch (e) {
      // Timed out, or the service/permission went away mid-request. Prefer a
      // slightly stale real position over reporting "nowhere" — every caller
      // reads null as "nothing nearby", which is a different and wrong claim.
      debugPrint('[location] fresh fix failed ($e) — trying last known');
      try {
        // Bounded too: this call can hang on Android, and an unbounded fallback
        // turned a 10s timeout into a stall with no output and no result — the
        // caller waited indefinitely with the loader up. Reading a cached
        // position should be near-instant, so a short limit costs nothing.
        final last = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 3));
        if (last != null) {
          final here = ExploreLatLng(last.latitude, last.longitude);
          _remember(here);
          return here;
        }
      } catch (e2) {
        debugPrint('[location] last-known unavailable: $e2');
      }
      // Fall back to whatever this session already saw before giving up. Past
      // the TTL it is stale for navigation but still better than no map at all.
      if (_cached != null) {
        debugPrint('[location] using expired cached fix');
        return _cached;
      }
      return null;
    }
  }

  @override
  Stream<ExploreLatLng> get locationUpdates => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).map((p) {
        final here = ExploreLatLng(p.latitude, p.longitude);
        // Seed the shared cache: while the map is open the device already has a
        // fix, so the AR tab should never start a cold request.
        _remember(here);
        return here;
      }).handleError((Object e) {
        // A denied/disabled location service makes the platform stream emit an
        // error (iOS: kCLErrorDomain 1 = denied). Unhandled, it surfaces as a
        // crash-level "Unhandled Exception" and the map just never populates.
        // Swallow it so the stream simply stops: permission state is what drives
        // the UI, via checkPermission() + the module's location-required screen.
        debugPrint('[location] position stream error (permission/service?): $e');
      });

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
