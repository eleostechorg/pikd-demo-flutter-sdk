import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:pikd_flutter_demo/geolocator_location_provider.dart';

/// Covers the behaviour behind a real bug: on a fresh install, opening the AR tab
/// first showed a live camera with no assets and no controls, and only worked
/// after visiting Explore. The cause was a bare `getCurrentPosition()` — best
/// accuracy, no time limit, no fallback — whose failure every caller read as
/// "nothing nearby". Explore's position stream happened to warm the platform
/// provider, which is why the detour "fixed" it.
void main() {
  late _FakeGeolocator fake;

  setUp(() {
    // The cache is process-wide by design, so it outlives a test unless cleared.
    GeolocatorExploreLocationProvider.resetCache();
    fake = _FakeGeolocator();
    GeolocatorPlatform.instance = fake;
  });

  test('asks for coarse accuracy and a time limit, not an unbounded best fix', () async {
    fake.current = _pos(6.667, 3.339);

    final here = await GeolocatorExploreLocationProvider().getCurrentLocation();

    expect(here, isNotNull);
    expect(here!.latitude, closeTo(6.667, 1e-9));
    // The regression to guard: LocationAccuracy.best on Android waits for a GPS
    // lock, which indoors can take tens of seconds or never resolve.
    expect(fake.lastSettings!.accuracy, LocationAccuracy.medium);
    expect(fake.lastSettings!.timeLimit, isNotNull);
  });

  test('a second call inside the TTL reuses the fix instead of asking again', () async {
    fake.current = _pos(6.667, 3.339);

    await GeolocatorExploreLocationProvider().getCurrentLocation();
    // A different instance: callers construct one per screen, and the AR tab must
    // benefit from a fix the map already paid for.
    final again = await GeolocatorExploreLocationProvider().getCurrentLocation();

    expect(again, isNotNull);
    expect(fake.currentCalls, 1);
  });

  test('concurrent callers share one platform request', () async {
    final gate = Completer<Position>();
    fake.gate = gate;

    final a = GeolocatorExploreLocationProvider().getCurrentLocation();
    final b = GeolocatorExploreLocationProvider().getCurrentLocation();
    gate.complete(_pos(6.667, 3.339));

    expect(await a, isNotNull);
    expect(await b, isNotNull);
    expect(fake.currentCalls, 1);
  });

  test('a timed-out fix falls back to the last known position', () async {
    fake.throwOnCurrent = true;
    fake.lastKnown = _pos(6.5, 3.4);

    final here = await GeolocatorExploreLocationProvider().getCurrentLocation();

    // A slightly stale real position beats reporting "nowhere", which callers
    // would render as an empty world.
    expect(here, isNotNull);
    expect(here!.latitude, closeTo(6.5, 1e-9));
    expect(fake.lastKnownCalls, 1);
  });

  test('falls back to an expired cached fix before giving up', () async {
    fake.current = _pos(6.667, 3.339);
    await GeolocatorExploreLocationProvider().getCurrentLocation();

    // Now the device stops answering and has no last-known position at all.
    fake.throwOnCurrent = true;
    fake.lastKnown = null;
    // Past the TTL the cache is no longer preferred, so _resolve() runs and has
    // to reach the expired-cache branch.
    GeolocatorExploreLocationProvider.expireCacheForTest();

    final here = await GeolocatorExploreLocationProvider().getCurrentLocation();

    expect(here, isNotNull);
    expect(here!.latitude, closeTo(6.667, 1e-9));
  });

  test('returns null only when there is genuinely nothing to report', () async {
    fake.throwOnCurrent = true;
    fake.lastKnown = null;

    final here = await GeolocatorExploreLocationProvider().getCurrentLocation();

    // Callers turn this into LocationUnavailableException rather than an empty
    // collectible list, so the UI can say "check your location settings".
    expect(here, isNull);
  });
}

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// Counts calls and records the settings the provider asks for, so the tests can
/// assert on *how* the position was requested, not just the value returned.
class _FakeGeolocator extends GeolocatorPlatform {
  Position? current;
  Position? lastKnown;
  bool throwOnCurrent = false;
  Completer<Position>? gate;

  int currentCalls = 0;
  int lastKnownCalls = 0;
  LocationSettings? lastSettings;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    currentCalls++;
    lastSettings = locationSettings;
    if (gate != null) return gate!.future;
    if (throwOnCurrent) throw TimeoutException('no fix');
    return current!;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) async {
    lastKnownCalls++;
    return lastKnown;
  }
}
