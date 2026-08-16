import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:pikd_flutter_ar/pikd_flutter_ar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:lottie/lottie.dart';
import 'package:pikd_flutter_api/api.dart' show ApiClient, CollectiblesApi, UserRefBody;
import 'package:pikd_flutter_ui/pikd_flutter_ui.dart';

import 'geolocator_location_provider.dart' show LocationUnavailableException;

/// The AR/camera screen, mirroring the RN camera tab. `pikd_flutter_ui` stays AR-agnostic;
/// the AR engine lives here in the host.
///
/// Two modes: **pinned** (from Explore's Collect CTA — only [collectible]) and
/// **unpinned** (the AR tab — everything nearby, one at a time via [_index]).
/// Collect fires on tapping the asset or the Collect button.
class ExploreArCollectScreen extends StatefulWidget {
  const ExploreArCollectScreen({
    super.key,
    this.collectible,
    this.nearbySource,
    required this.base,
    required this.sdkKey,
    this.userRef,
    this.onClose,
    this.onViewProfile,
  });

  /// RN's `pinnedAssetId`. Set when arriving from Explore's Collect CTA — only this
  /// asset is placed. Null as the AR tab, which places everything nearby.
  final ExploreCollectible? collectible;

  /// Supplies nearby assets for the **unpinned** mode. Required when
  /// [collectible] is null; ignored when pinned. Kept as a callback so the screen
  /// doesn't care whether it's fed by the live repository or sample data.
  final Future<List<ExploreCollectible>> Function()? nearbySource;

  final String base;
  final String sdkKey;
  final String? userRef;

  /// How to leave. Null pops the route — correct when Explore pushed us, but as a
  /// tab there's nothing to pop and popping blanks the app, so a host embedding this
  /// as a tab must pass it. RN navigates to a tab here rather than popping.
  final VoidCallback? onClose;

  /// Leave and show the collected item — RN's `arCamera.showCollected.button`
  /// ("Go to profile"). Falls back to [onClose], then to popping.
  final VoidCallback? onViewProfile;

  @override
  State<ExploreArCollectScreen> createState() => _ExploreArCollectScreenState();
}

/// The theme font for raw [Text] styles (PikdText already routes it). Ensures a
/// host font rebrand reaches every label in this screen, not just the colours.
String? _themeFont(BuildContext context) => PikdThemeProvider.of(context).typography.fontFamily;

/// The native SDK initializes once per app run. Re-initializing an
/// already-initialized SDK on screen re-entry breaks placement; `stopArSession`
/// (on close) stops the session but leaves the SDK initialized, so re-entry only
/// restarts the session + re-places.
bool _pikdInitialized = false;

class _ExploreArCollectScreenState extends State<ExploreArCollectScreen> {
  late final CollectiblesApi _api;
  StreamSubscription<ArEvent>? _sub;

  /// Completes on the `ArSessionStarted` event. We can't rely on awaiting
  /// `PikdAr.startArSession()` — see the note in [_start].
  Completer<void>? _sessionStarted;

  /// Resolves on the `AssetPlaced` event for [_awaitingPlacementOf].
  ///
  /// `placeAssetOnSurface()` returning is NOT placement. Native tries a
  /// centre-screen hit test, then instant placement, and if both fail it quietly
  /// enters tap-to-place mode — the call still completes normally. Only
  /// `didPlaceAssetOnSurface` → `onAssetPlaced` means a render node exists, so
  /// that event is the single honest signal.
  Completer<void>? _placementConfirmed;
  String? _awaitingPlacementOf;

  bool _arReady = false; // gates PikdArView (mount only after permissions)
  bool _loading = false; // asset model downloading/placing → radar loader
  int? _loadPercent; // AssetProgress → "Loading assets... N%"
  bool _placed = false; // the current asset is in the scene → collect enabled
  bool _collecting = false; // collect POST in flight
  bool _collected = false; // success → show the "Item collected" modal
  bool _collectFailed = false; // → RN's collect-failed dialog (Retry / Cancel)
  bool _permissionDenied = false; // → RN NoCameraAccess screen
  bool _unsupported = false; // CURRENT asset has no model for this platform → toast
  String _status = 'Starting AR…'; // AR init-error debug fallback

  /// Every nearby collectible — the "Available: N" count. Pinned mode holds
  /// exactly one.
  List<ExploreCollectible> _targets = const [];

  /// Which of [_targets] is in the scene. RN's camera is a carousel — one asset at a
  /// time, arrows swap it — and instant placement pins each ~2 m ahead, so placing
  /// them all at once would stack the set on one spot.
  int _index = 0;

  /// The collectible currently placed, keyed by the assetId we loaded it under (we
  /// use the collectible id, so a tap's targetId maps straight back).
  final Map<String, ExploreCollectible> _placedById = {};

  /// Set by [_searchNearby] — RN clears `pinnedAssetId` to switch a pinned session
  /// into all-nearby mode.
  bool _pinCleared = false;

  bool get _isPinned => widget.collectible != null && !_pinCleared;

  /// Android-only demo regression check for hosts that use AndroidX
  /// FragmentActivity biometric integrations.
  ///
  /// This belongs on the real collect screen rather than the lightweight package
  /// example so a tester can authenticate before and after the complete
  /// Explore → Collect → AR → close → re-enter lifecycle. [kDebugMode] removes
  /// the control from release builds; it is not PIKD product UI or SDK API.
  Future<void> _verifyBiometricCompatibility() async {
    final auth = LocalAuthAndroid();
    try {
      if (!await auth.isDeviceSupported()) {
        if (mounted) {
          PikdToast.show(
            context,
            type: PikdToastType.info,
            title: 'Biometrics unavailable',
            description: 'This device does not support biometric authentication.',
          );
        }
        return;
      }

      final authenticated = await auth.authenticate(
        localizedReason: 'Verify biometric authentication alongside PIKD AR.',
        authMessages: const [],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      PikdToast.show(
        context,
        type: authenticated ? PikdToastType.success : PikdToastType.info,
        title: authenticated ? 'Biometric check passed' : 'Biometric check cancelled',
        description: authenticated
            ? 'Authentication works while the PIKD AR flow is active.'
            : 'Try again when you are ready to authenticate.',
      );
    } catch (error) {
      if (!mounted) return;
      PikdToast.show(
        context,
        type: PikdToastType.failed,
        title: 'Biometric check failed',
        description: '$error',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    final client = ApiClient(basePath: widget.base)..addDefaultHeader('x-pikd-sdk-key', widget.sdkKey);
    _api = CollectiblesApi(client);
    _start();
  }

  Future<void> _start() async {
    try {
      debugPrint('[COLLECT] _start ENTER (pikdInitialized=$_pikdInitialized)');
      // Camera + location grant must precede the session; mount the view BEFORE
      // initialize()/startArSession() or the renderer no-ops → black camera.
      if (!await PikdAr.requestArPermissions()) {
        if (mounted) setState(() => _permissionDenied = true);
        return;
      }
      // Show the loader through the WHOLE setup (init + session + load), so a
      // slow/failed step is never a silent black screen.
      if (mounted) setState(() { _arReady = true; _loading = true; _loadPercent = null; });

      // Initialize once per app run; the instant-placement config from the first
      // init persists for later sessions. Tolerate an already-initialized SDK on
      // re-entry (the native side stays initialized after stopArSession).
      if (!_pikdInitialized) {
        try {
          await PikdAr.initialize(PikdArConfig(
            userId: widget.userRef ?? 'anon',
            apiBaseUrl: widget.base,
            authToken: widget.sdkKey,
            mockGps: true,
            // RN collect UX: instant placement (~2 m in front), not plane-hunt,
            // and the tap recognizer installed. Forwarded to native PIKDConfig.
            extra: const {
              'gestureModels': ['tap', 'pinch', 'drag'],
              'surfaceDetection': {'enabled': false},
              'iosPlacement': {
                'enableInstantPlacementFallback': true,
                'instantPlacementApproximateDistanceMeters': 2.0,
              },
              'androidPlacement': {
                'enableInstantPlacementFallback': true,
                'instantPlacementApproximateDistanceMeters': 2.0,
              },
            },
          ));
        } catch (_) {
          // Already initialized (e.g. hot-restart desync) — safe to proceed.
        }
        _pikdInitialized = true;
      }
      // Subscribe BEFORE starting: the session-started event can land immediately,
      // and asset progress must not be missed either. Drop any previous
      // subscription first — [_retry] re-enters here, and a second listener would
      // double-handle every tap.
      await _sub?.cancel();
      _sub = PikdAr.events.listen(_onEvent);

      // Do NOT start the session from here — the VIEW owns it. PikdArView
      // auto-starts on window attach on both platforms (iOS
      // FlutterPikdArViewFactory.didMoveToWindow, Android
      // onAttachedToWindow -> waitForLayoutThenStart), mirroring RN's
      // PIKDARViewContainer; each also handles the not-yet-initialized case
      // itself (iOS retries, Android waits on a session-state listener).
      //
      // Calling startArSession() as well creates a genuine double-start: both
      // land in ARManager.runSession, which keeps ONE pending-completion slot, so
      // the view's (completion-less) start replaces ours and the frame that would
      // have flushed it calls nobody — an await here hangs forever, and the
      // duplicated start leaves native session state inconsistent across a
      // close/reopen. RN never does this. So we just wait for the event.
      debugPrint('[COLLECT] awaiting ArSessionStarted from the view '
          '(${widget.collectible == null ? "unpinned/nearby" : "pinned ${widget.collectible!.id}"})');
      _sessionStarted = Completer<void>();
      // A re-entry may find the session already running, in which case no new
      // event fires — so time out and proceed rather than block.
      await _sessionStarted!.future.timeout(const Duration(seconds: 8), onTimeout: () {
        debugPrint('[COLLECT] no ArSessionStarted within 8s — proceeding anyway');
      });
      debugPrint('[COLLECT] session ready + subscribed');
      await _loadAndPlaceTargets();
    } catch (e, st) {
      // Never leave a silent blank — drop the loader and surface the error.
      debugPrint('[COLLECT] _start error: $e\n$st');
      if (mounted) setState(() { _loading = false; _status = 'AR error: $e'; });
    }
  }

  /// Plays `animations[0]` looped, as RN's `<ARAsset>` does.
  ///
  /// Order matters: only **after** placement (native needs an instance), and RN
  /// waits 1200 ms after it because placement completes asynchronously. Playing
  /// immediately silently does nothing — that's why nothing animated here.
  Future<void> _playFirstAnimation(Asset asset) async {
    if (asset.animations.isEmpty) {
      debugPrint('[COLLECT] asset has no animations — nothing to play');
      return;
    }
    final clip = asset.animations.first;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    try {
      await PikdAr.playAssetAnimation(asset.id, clip, loop: true);
      debugPrint("[COLLECT] playing animation '$clip' (loop) "
          'of ${asset.animations.length}: ${asset.animations}');
    } catch (e) {
      // Non-fatal: a static-looking collectible is better than a broken screen.
      debugPrint('[COLLECT] playAssetAnimation failed: $e');
    }
  }


  /// Resolves the target list — the pinned collectible, or everything nearby when
  /// unpinned — then places the one at [_index]. Split out of [_start] so RN's
  /// "Search Nearby" can re-scan without re-running permissions/init or waiting on
  /// the session event again.
  /// Guards against two chains running at once.
  ///
  /// [_start] and [_searchNearby] both call this, and the location provider now
  /// shares one in-flight fix between callers — so two entries that arrive while
  /// a fix is pending resume together and each run a full load-and-place. That
  /// duplicated the download, the progress stream feeding one loader, and the
  /// placement itself.
  bool _loadInFlight = false;

  Future<void> _loadAndPlaceTargets() async {
    if (_loadInFlight) {
      debugPrint('[COLLECT] load already in flight — ignoring duplicate request');
      return;
    }
    _loadInFlight = true;
    try {
      // Pinned: just this asset. Unpinned (AR/camera tab): everything nearby —
      // RN passes `pinnedAssetId ?? undefined` into its nearby fetch for exactly
      // this reason.
      final List<ExploreCollectible> targets;
      if (_isPinned) {
        targets = [widget.collectible!];
      } else {
        targets = await (widget.nearbySource?.call() ?? Future.value(const <ExploreCollectible>[]));
        debugPrint('[COLLECT] unpinned mode: ${targets.length} nearby');
      }
      if (!mounted) return;
      setState(() {
        _targets = targets;
        _index = 0;
      });
      if (targets.isEmpty) {
        // RN's `noNearestNFT` only gates the loader — the `noNearestNFTModal`
        // strings exist in its locale file but no component renders them (checked
        // across src/). The HUD's "Available: 0" is the whole signal, so drop the
        // loader and leave a live camera up, exactly as RN behaves.
        setState(() => _loading = false);
        return;
      }
      await _placeCurrent();
    } catch (e, st) {
      debugPrint('[COLLECT] load/place error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        // A missing position is not an AR failure and must not read as one — the
        // user can act on it, unlike an SDK error.
        _status = e is LocationUnavailableException
            ? 'Waiting for your location.\nCheck location permission and that GPS is on.'
            : 'AR error: $e';
      });
    } finally {
      // Runs even on the early returns above, so a failed load never wedges the
      // guard shut and block every later attempt.
      _loadInFlight = false;
    }
  }

  /// Loads + places `_targets[_index]` — the only asset in the scene at a time.
  Future<void> _placeCurrent() async {
    if (_index < 0 || _index >= _targets.length) return;
    final c = _targets[_index];
    final url = defaultTargetPlatform == TargetPlatform.iOS
        ? c.assetModelUrlIos
        : c.assetModelUrlAndroid;
    if (url == null || url.isEmpty) {
      // RN treats "no model for this platform" as a property of the CURRENT asset
      // (`setIsCurrentAssetUnsupported`) and surfaces it as a **toast**, leaving the
      // HUD and arrows up so you can move past it — it never takes the screen down.
      debugPrint('[COLLECT] ${c.id}: no model for this platform');
      if (!mounted) return;
      setState(() { _unsupported = true; _loading = false; _placed = false; });
      _showUnsupported();
      return;
    }
    try {
      debugPrint('[COLLECT] loadAsset begin id=${c.id} (${_index + 1}/${_targets.length})');
      final asset = await PikdAr.loadAsset(url, c.id);
      // Pin it — a collectible shouldn't drift/fall (RN sets physicsType="static").
      await PikdAr.setAssetBehaviorOptions(
        asset.id,
        const AssetBehaviorOptions(physicsType: 'static'),
      );
      if (!await _placeAndConfirm(asset.id)) {
        // Instant placement needs no user action — it does not hunt for a plane,
        // so "move your phone" would be advice the user cannot act on. Getting
        // here means the retries were exhausted, which is a fault to state
        // plainly rather than to blame on how the device is being held.
        debugPrint('[COLLECT] placement unconfirmed for ${asset.id}');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _placed = false;
          _status = "Couldn't place the collectible.";
        });
        return;
      }
      debugPrint('[COLLECT] placed assetId=${asset.id}');
      if (!mounted) return;
      setState(() {
        _placedById
          ..clear()
          ..[asset.id] = c;
        _loading = false;
        _placed = true;
        _unsupported = false;
      });
      // Chrome first, animation in the background — its settle delay must not
      // hold the loader up.
      _playFirstAnimation(asset);
    } catch (e) {
      debugPrint('[COLLECT] load/place failed for ${c.id}: $e');
      if (mounted) setState(() { _loading = false; _status = 'AR error: $e'; });
    }
  }

  /// Asks native to place [assetId] and waits for it to confirm, retrying while
  /// the session warms up.
  ///
  /// Retries like RN's `requestGuidePlacement` (ExploreARNavigationScreen), but
  /// with a longer budget, because failure here has no user-actionable remedy.
  ///
  /// Placement is instant-placement only: this screen disables surface
  /// detection, so nothing is hunting for a plane and there is nothing for the
  /// user to do differently. Explore → Collect fails purely on timing — pinned
  /// mode has no nearby fetch to sit through, so placement runs ~2 ms after
  /// `ArSessionStarted`, when ARCore has processed too few frames to offer even
  /// an instant-placement point. It resolves itself within a second or two, so
  /// the right response is to keep the loader up and keep asking, not to bail
  /// early and show a message the user cannot act on.
  ///
  /// The camera tab only ever worked because its network round-trip happened to
  /// provide several seconds of warm-up.
  static const int _placementAttempts = 8;
  static const Duration _placementRetryDelay = Duration(milliseconds: 1200);

  Future<bool> _placeAndConfirm(String assetId) async {
    for (var attempt = 1; attempt <= _placementAttempts; attempt++) {
      _awaitingPlacementOf = assetId;
      final confirmed = _placementConfirmed = Completer<void>();
      await PikdAr.placeAssetOnSurface(assetId);
      try {
        await confirmed.future.timeout(_placementRetryDelay);
        return true;
      } on TimeoutException {
        debugPrint('[COLLECT] placement attempt $attempt/$_placementAttempts unconfirmed');
        if (!mounted) return false;
      }
    }
    // Deliberately leaves [_awaitingPlacementOf] set: a slow attempt can still
    // confirm after we stop waiting, and the event handler promotes that late
    // AssetPlaced to a real placement rather than dropping it.
    _placementConfirmed = null;
    return false;
  }

  /// RN's `handlePrevOrNext`: clear the visible asset, then load + place the one at
  /// the new index. Only one asset is ever in the scene.
  Future<void> _goTo(int index) async {
    if (index == _index || index < 0 || index >= _targets.length) return;
    setState(() {
      _index = index;
      _placed = false;
      _placedById.clear();
      _loading = true;
      _loadPercent = null;
      _unsupported = false;
    });
    await PikdAr.removeAllAssetsFromScene()
        .catchError((Object e) => debugPrint('[COLLECT] scene clear failed: $e'));
    await PikdAr.clearAssetCache()
        .catchError((Object e) => debugPrint('[COLLECT] cache clear failed: $e'));
    await _placeCurrent();
  }

  /// RN's `onSearchNearby` (pinned mode only): drop the pin and re-scan. RN clears
  /// `pinnedAssetId` then refreshes; we also clear the scene + asset cache first so
  /// the pinned asset doesn't linger beside the nearby ones.
  Future<void> _searchNearby() async {
    if (widget.nearbySource == null) return;
    setState(() {
      _pinCleared = true;
      _placed = false;
      _placedById.clear();
      _index = 0;
      _unsupported = false;
      _loading = true;
      _loadPercent = null;
    });
    await PikdAr.removeAllAssetsFromScene()
        .catchError((Object e) => debugPrint('[COLLECT] scene clear failed: $e'));
    await PikdAr.clearAssetCache()
        .catchError((Object e) => debugPrint('[COLLECT] cache clear failed: $e'));
    await _loadAndPlaceTargets();
  }

  void _onEvent(ArEvent e) {
    // Load progress → "Loading assets... N%" (RN onLoadProgress).
    // Session up — releases the wait in [_start].
    if (e is ArSessionStarted) {
      debugPrint('[COLLECT] event ArSessionStarted');
      if (_sessionStarted?.isCompleted == false) _sessionStarted!.complete();
      return;
    }
    if (e is AssetPlaced) {
      // The only trustworthy placement signal — native emits this from
      // didPlaceAssetOnSurface, once a render node genuinely exists.
      if (e.assetId != _awaitingPlacementOf) return;
      debugPrint('[COLLECT] placement confirmed for ${e.assetId}');
      final pending = _placementConfirmed;
      if (pending != null && !pending.isCompleted) {
        pending.complete(); // [_placeAndConfirm] is still waiting
        return;
      }
      // Arrived after we stopped waiting: a late attempt landed, so the asset
      // really is in the world and the screen has to catch up — otherwise the
      // failure message stays up and Collect never enables.
      _awaitingPlacementOf = null;
      if (!mounted) return;
      ExploreCollectible? target;
      for (final t in _targets) {
        if (t.id == e.assetId) {
          target = t;
          break;
        }
      }
      if (target == null) return; // not one of ours; nothing to enable
      setState(() {
        _placedById
          ..clear()
          ..[e.assetId] = target!;
        _loading = false;
        _placed = true;
        _unsupported = false;
      });
      return;
    }
    if (e is AssetProgress) {
      if (mounted && !_placed) {
        final rawPercent = (e.progress.clamp(0.0, 1.0) * 100).round();
        // Native progress can arrive for nearly every network chunk. Rebuilding
        // the full AR Stack and logging every event starves Hybrid Composition
        // on slower devices, so publish at most 21 human-visible updates.
        final visiblePercent = rawPercent >= 100 ? 100 : (rawPercent ~/ 5) * 5;
        if (visiblePercent != _loadPercent) {
          debugPrint('[COLLECT] AssetProgress $visiblePercent%');
          setState(() => _loadPercent = visiblePercent);
        }
      }
      return;
    }
    // RN: a tap on a placed asset comes back on targetId/instanceId/anchorId
    // (NOT assetId) — see its camera tap handler, which compares that target
    // against `currentPlacedAssetId` and ignores anything else. Only one asset is
    // ever in the scene, so the same check works here.
    if (e is Interaction) {
      if (_collecting || _collected || !_placed || e.gesture != 'tap') return;
      final hit = e.targetId ?? e.instanceId ?? e.anchorId ?? e.assetId;
      if (hit == null) return;
      final current = _currentPlacedId;
      if (current == null) return;
      // Accept an exact match, and otherwise still claim the current asset: native
      // instance ids don't always equal the assetId we loaded under, and with a
      // single asset in the scene a tap can't be ambiguous.
      if (hit != current) {
        debugPrint('[COLLECT] tap target $hit != current $current — claiming current');
      }
      _collect(current);
    }
  }

  /// The assetId of the asset in the scene (RN's `currentPlacedAssetId`).
  String? get _currentPlacedId => _placedById.isEmpty ? null : _placedById.keys.first;

  /// Claims [collectibleId] — the asset the user actually tapped, which matters
  /// once several are on screen in unpinned mode.
  Future<void> _collect(String collectibleId) async {
    if (_collecting || _collected) return;
    setState(() => _collecting = true);
    try {
      final res = await _api.collectCollectible(
        collectibleId,
        userRefBody: widget.userRef == null ? null : UserRefBody(userRef: widget.userRef!),
      );
      if (!mounted) return;
      final status = res?.status.value;
      // Logged because the status is the only channel the API has for this: there
      // is no remaining-count or reset-at field anywhere on the asset or response.
      debugPrint('[COLLECT] collect $collectibleId -> status=$status');
      if (status == 'collected') {
        // Success → the "Item collected" modal (RN CustomDialogBox success).
        setState(() { _collecting = false; _collected = true; });
      } else if (status == 'instance_maxed_out' || status == 'threshold_exceeded') {
        // Repeatable asset with no collections left — not awarded, and distinct
        // from a genuine failure. The asset stays on the map (the backend keeps
        // returning it), so we just surface the limit. Live staging returns
        // `instance_maxed_out`; `threshold_exceeded` is the value in the API docs
        // example, so accept both.
        setState(() => _collecting = false);
        _showCollectLimitReached();
      } else {
        // Non-success surfaces as RN's collect-error copy (handleCollectError).
        // RN's toast carries the server's `message`; /sdk/v1 CollectResult has no
        // message field, so the unexpected status is the most useful stand-in —
        // and it's exactly how we caught `instance_maxed_out` not matching the docs.
        setState(() => _collecting = false);
        _showCollectError(status == null ? null : 'Unexpected status: $status');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _collecting = false);
        _showCollectError();
      }
    }
  }

  /// RN `arCamera.unsupportedModal.*` — despite the key name RN surfaces this as a
  /// warning **toast** (`showToast`) and keeps the camera up. Our case is the
  /// missing-platform-URL variant, so the copy is RN's `*MissingUrl` pair verbatim.
  void _showUnsupported() {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    PikdToast.show(
      context,
      type: PikdToastType.warning,
      title: isIos ? 'Missing iOS 3D file' : 'Missing Android 3D file',
      description: isIos
          ? 'This asset does not include an iOS-ready 3D file. iOS requires USDZ format.'
          : 'This asset does not include an Android-ready 3D file. Android requires GLB or GLTF format.',
    );
  }

  /// RN's `handleCollectError` does two things: a warning toast carrying the
  /// server's message, AND a "failed" dialog with Retry/Cancel
  /// (`camera.collect.title` + `collectFailedText`). We mirror both — the toast
  /// says *what* went wrong, the dialog is the acknowledgement.
  void _showCollectError([String? message]) {
    PikdToast.show(
      context,
      type: PikdToastType.warning,
      title: 'Info',
      description: message ?? 'Something went wrong. Please try again.',
    );
    setState(() => _collectFailed = true);
  }

  /// The asset can't be collected any more (`instance_maxed_out`) — informational,
  /// not a failure, so it gets a toast and no dialog. Net-new to our SDK; RN has no
  /// equivalent surface.
  ///
  /// Reads as permanent, with no time promise: the cap is global per asset and never
  /// resets (backend-confirmed), so once the instances are gone it's done for
  /// everyone. We used to say "check back tomorrow", which was wrong.
  void _showCollectLimitReached() {
    PikdToast.show(
      context,
      type: PikdToastType.info,
      title: 'Fully collected',
      description: 'Every one of these has been claimed — nothing left to collect here.',
    );
  }

  /// The single way out, so no exit path gets forgotten. Pops only as a last resort:
  /// as a tab there's no route to pop and popping blanked the app.
  void _exit() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    // Pushed-route mode (Explore -> Collect): pop back to where we came from. Guard
    // it so a missing host callback can never blank the app again.
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  /// Leave and show the collected item (RN's "Go to profile").
  void _exitToProfile() {
    final onViewProfile = widget.onViewProfile;
    if (onViewProfile != null) {
      onViewProfile();
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop('collected');
      return;
    }
    _exit();
  }

  Future<void> _retry() async {
    setState(() {
      _permissionDenied = false;
      _unsupported = false;
      _status = 'Starting AR…';
    });
    await _start();
  }

  @override
  void dispose() {
    debugPrint('[COLLECT] dispose → clear scene + cache, then stop session');
    _sub?.cancel();
    // Order is load-bearing (mirrors RN's camera unmount): clear the scene AND the
    // asset cache — PIKDARKit keys entities by assetId, so skipping the cache makes
    // the next load silently no-op — while the session is still alive, and stop the
    // session last. Fire-and-forget so a slow native call can't wedge teardown.
    PikdAr.removeAllAssetsFromScene()
        .catchError((Object e) => debugPrint('[COLLECT] removeAllAssetsFromScene failed: $e'));
    PikdAr.clearAssetCache()
        .catchError((Object e) => debugPrint('[COLLECT] clearAssetCache failed: $e'));
    PikdAr.stopArSession()
        .catchError((Object e) => debugPrint('[COLLECT] stopArSession failed: $e'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;

    // Permission denied → RN NoCameraAccess full screen (instead of the camera).
    if (_permissionDenied) {
      return Scaffold(
        backgroundColor: c.background,
        body: _PermissionScreen(
          onContinue: _retry,
          onOpenSettings: Geolocator.openAppSettings,
          onClose: _exit,
        ),
      );
    }

    // RN gates its HUD/arrows/CTA on `hasAssets` (assetsCount > 0), NOT on whether
    // the current one finished placing — so an unsupported or still-loading asset
    // leaves the arrows reachable. The CTA is rendered but *disabled* instead
    // (`collectDisabled` folds in isCurrentAssetUnsupported + the loader).
    final showChrome = _targets.isNotEmpty && !_collected;
    final collectDisabled = !_placed || _loading || _unsupported;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          // AR camera (or bg until permissions granted).
          if (_arReady) const PikdArView() else ColoredBox(color: c.background),

          // Asset-loader overlay (RN camera: radar Lottie + "Loading assets... N%"
          // over a dim scrim). Surface detection is off, so — like RN — there's
          // no "find a surface" prompt; instant placement follows the load.
          if (_loading)
            Positioned.fill(
              child: ColoredBox(
                color: c.overlay,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Lottie.asset('assets/lotties/radar.json', package: 'pikd_flutter_ui', width: 160, height: 160),
                      Text(
                        _loadPercent != null ? 'Loading assets... $_loadPercent%' : 'Loading assets...',
                        style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // AR init-error fallback line (a real exception; not RN-modelled copy).
          if (!_placed && !_loading && !_collected && !_unsupported && _status != 'Starting AR…')
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: _FrostedPill(
                  tint: c.overlay,
                  child: Text(_status, textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 15)),
                ),
              ),
            ),

          // Top-left HUD — RN ARCameraTopHud non-game panel: a dark panel with a
          // "NEARBY" caps label + the available/position value.
          if (showChrome)
            Positioned(
              top: 52,
              left: 16,
              child: _HudPanel(
                isPinned: _isPinned,
                onSearchNearby: widget.nearbySource == null ? null : _searchNearby,
                availableCount: _targets.length,
                currentPosition: _index + 1,
              ),
            ),

          // Prev/next asset arrows — RN ARControllers renders a left arrow when
          // `index !== 0` and a right arrow when `index !== assets.length - 1`,
          // vertically at ~SCREEN_HEIGHT / 2.5, and they swap which single asset is
          // in the scene. Hidden in pinned mode, which has exactly one target.
          if (showChrome && _index > 0)
            Positioned(
              top: MediaQuery.sizeOf(context).height / 2.5,
              left: 16,
              child: _LiquidGlassButton(
                tint: c.glass,
                onTap: () => _goTo(_index - 1),
                child: SvgPicture.asset('assets/icons/arrow-left.svg', width: 24, height: 24,
                    colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn)),
              ),
            ),
          if (showChrome && _index < _targets.length - 1)
            Positioned(
              top: MediaQuery.sizeOf(context).height / 2.5,
              right: 16,
              child: _LiquidGlassButton(
                tint: c.glass,
                onTap: () => _goTo(_index + 1),
                // RN uses its green arrow glyph here (pikdArrowRightGreen) — the
                // "keep going" direction — so tint this one with the brand accent.
                child: SvgPicture.asset('assets/icons/arrow-right.svg', width: 24, height: 24,
                    colorFilter: ColorFilter.mode(c.activeAccent, BlendMode.srcIn)),
              ),
            ),

          // Top-right close (RN LiquidButton isBlack, pikdCancelWhite glyph).
          Positioned(
            top: 52,
            right: 16,
            child: _LiquidGlassButton(
              tint: c.glass,
              onTap: _exit,
              child: SvgPicture.asset('assets/icons/close.svg', width: 24, height: 24,
                  colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn)),
            ),
          ),

          // The actual demo screen is the only meaningful place to verify that
          // Android FragmentActivity plugins still work through AR close/re-entry.
          // This is an Android-only regression fixture: iOS has no comparable
          // host-activity contract. Debug builds expose it; production builds
          // elide it entirely via the compile-time [kDebugMode] constant.
          if (kDebugMode && defaultTargetPlatform == TargetPlatform.android)
            Positioned(
              top: 52,
              right: 72,
              child: Semantics(
                button: true,
                label: 'Verify biometric authentication',
                child: _LiquidGlassButton(
                  tint: c.glass,
                  onTap: _verifyBiometricCompatibility,
                  child: Icon(Icons.fingerprint, size: 24, color: c.textPrimary),
                ),
              ),
            ),

          // Bottom-centre Collect button (RN v2Primary box + pikdV2Collect glyph).
          if (showChrome)
            Positioned(
              left: 0, right: 0, bottom: 40,
              child: Center(
                child: _CollectButton(
                  busy: _collecting,
                  disabled: collectDisabled,
                  bg: c.primary,
                  fg: c.onPrimary,
                  // Claims whichever asset is in the scene — there's only ever one,
                  // and the arrows are how you get to the others (RN collects
                  // `currentPlacedAssetId`).
                  onTap: () {
                    final id = _currentPlacedId;
                    if (id != null) _collect(id);
                  },
                ),
              ),
            ),

          // "Item collected" success modal (RN CustomDialogBox: firework Lottie
          // + check icon + heading + 2-line copy + Go-to-profile / Cancel).
          if (_collected)
            _CollectedModal(
              onGoToProfile: _exitToProfile,
              onCancel: _exit,
            ),

          // Collect-failed dialog — RN's CustomDialogBox type="failed": the
          // `camera.collect.title` heading, collectFailedText body, and a Retry
          // primary in the error colour plus Cancel. Both of RN's buttons just
          // close it (it doesn't re-fire the collect), so ours do the same.
          if (_collectFailed)
            _CollectFailedModal(
              onDismiss: () => setState(() => _collectFailed = false),
            ),

        ],
      ),
    );
  }
}

/// Frosted, tinted round button — Flutter stand-in for RN's liquid-glass
/// `LiquidButton` (blur + themed [glass] tint, 24 dp glyph).
class _LiquidGlassButton extends StatelessWidget {
  const _LiquidGlassButton({required this.child, required this.tint, required this.onTap});

  final Widget child;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(24)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// RN's bottom-centre collect CTA: a solid primary rounded box with the
/// `v2-collect` glyph + "Collect" label.
class _CollectButton extends StatelessWidget {
  const _CollectButton({
    required this.busy,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.disabled = false,
  });

  final bool busy;
  final bool disabled;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inert = busy || disabled;
    return Opacity(
      // RN's collectDisabled dims the CTA rather than removing it, so the control
      // stays where the user expects while the current asset loads.
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        onTap: inert ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 16),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              busy
                  ? SizedBox(width: 36, height: 36,
                      child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(fg)))
                  : SvgPicture.asset('assets/icons/collect.svg', width: 36, height: 36,
                      colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
              const SizedBox(height: 6),
              PikdText('Collect', role: PikdTextRole.label, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-left HUD, mirroring RN's `ARCameraTopHud` non-game panel: a solid dark
/// panel with a small caps "NEARBY" label above a value line.
///
/// Copy is RN's verbatim (`languages/english.json`): `arCamera.hud.nearby` =
/// "Nearby", `arCamera.available` = "Available: {{count}}" and — when more than one
/// asset is in range — `arCamera.availableWithPosition` =
/// "Available: {{count}} · {{current}}/{{total}}". In pinned mode
/// `camera.pinnedAsset.label` = "1 asset" with a ghost
/// `camera.pinnedAsset.searchNearby` = "Search Nearby" action — RN renders that
/// action only when `isPinnedAsset && onSearchNearby`.
class _HudPanel extends StatelessWidget {
  const _HudPanel({
    required this.availableCount,
    required this.currentPosition,
    this.isPinned = false,
    this.onSearchNearby,
  });

  final int availableCount;
  final int currentPosition;
  final bool isPinned;
  final VoidCallback? onSearchNearby;

  /// RN shows the position suffix only when there's more than one asset to move
  /// between (`showAssetPosition = assetsCount > 1`).
  String get _value {
    if (isPinned) return '1 asset';
    if (availableCount > 1) {
      return 'Available: $availableCount · $currentPosition/$availableCount';
    }
    return 'Available: $availableCount';
  }

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NEARBY',
              style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary, fontSize: 9, letterSpacing: 0.6, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(_value,
              style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          // RN: ghost "Search Nearby" action, pinned mode only — clears the pin and
          // re-scans, so a user who came from one map pin isn't stuck with it.
          if (isPinned && onSearchNearby != null) ...[
            Divider(height: 10, thickness: 0.5, color: c.border),
            GestureDetector(
              onTap: onSearchNearby,
              child: Text('Search Nearby',
                  style: TextStyle(
                      fontFamily: _themeFont(context),
                      color: c.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A frosted, tinted rounded container (coaching / error hint).
class _FrostedPill extends StatelessWidget {
  const _FrostedPill({required this.child, required this.tint});

  final Widget child;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(16)),
          child: child,
        ),
      ),
    );
  }
}

/// "Item collected" success modal — the RN camera's `CustomDialogBox`
/// (`type="success"`, `isCongratsLottie`): a blurred scrim behind a centred card
/// with the firework Lottie, the `check.png` badge, heading, 2-line copy, and a
/// "Go to profile" primary + Cancel. Copy verbatim from RN
/// `arCamera.showCollected.*`. All colours route through [PikdTheme].
class _CollectedModal extends StatelessWidget {
  const _CollectedModal({required this.onGoToProfile, required this.onCancel});

  final VoidCallback onGoToProfile;
  final VoidCallback onCancel;

  static const _heading = 'Item collected';
  static const _description =
      "Congrats, you've collected a new item! Check it out!\n\n"
      'Go to your profile to view all of your collected items and keep track of '
      "challenges you've taken part in.";

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: c.overlay,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/images/check.png', width: 96, height: 96),
                        const SizedBox(height: 16),
                        Text(_heading, textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Text(_description, textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary, fontSize: 14, height: 1.4)),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.primary,
                              foregroundColor: c.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: onGoToProfile,
                            child: PikdText('Go to profile', role: PikdTextRole.label, color: c.onPrimary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: onCancel,
                          child: Text('Cancel', style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary)),
                        ),
                      ],
                    ),
                  ),
                  // Congrats firework overplayed above the card (RN isCongratsLottie).
                  Positioned(
                    top: -70,
                    child: IgnorePointer(
                      child: Lottie.asset('assets/lotties/firework.json', package: null, width: 220, height: 220, repeat: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// RN `NoCameraAccess` — a full screen shown instead of the camera when the AR
/// permission is denied: a lime icon circle + "Camera Access" heading + copy +
/// Continue / Open Settings. Copy verbatim from `arCamera.permissions.camera.*`.
class _PermissionScreen extends StatelessWidget {
  const _PermissionScreen({required this.onContinue, required this.onOpenSettings, required this.onClose});

  final VoidCallback onContinue;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surfaceBrand, shape: BoxShape.circle),
                  child: SvgPicture.asset('assets/icons/camera.svg', width: 40, height: 40,
                      colorFilter: ColorFilter.mode(c.onSurfaceBrand, BlendMode.srcIn)),
                ),
                const SizedBox(height: 24),
                Text('Camera Access', textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  'To display AR collectibles and let you play AR-based games in the real world, '
                  'Pikd needs access to your camera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary, fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: 300,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      foregroundColor: c.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: onContinue,
                    child: PikdText('Continue', role: PikdTextRole.label, color: c.onPrimary),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onOpenSettings,
                  child: Text('Open Settings', style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary)),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 52, right: 16,
          child: _LiquidGlassButton(
            tint: c.glass,
            onTap: onClose,
            child: SvgPicture.asset('assets/icons/close.svg', width: 24, height: 24,
                colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn)),
          ),
        ),
      ],
    );
  }
}

/// RN's collect-failed `CustomDialogBox` (`type="failed"`): the warning badge,
/// the `camera.collect.title` heading, the `collectFailedText` body, and a Retry
/// primary tinted with the error colour plus a Cancel. Copy verbatim.
class _CollectFailedModal extends StatelessWidget {
  const _CollectFailedModal({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;
    return Positioned.fill(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: c.overlay,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/warning.png', width: 96, height: 96),
                    const SizedBox(height: 16),
                    Text('Collect', textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: _themeFont(context), color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(
                      'Oops! It looks like there was an issue acquiring this digital collectible.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary, fontSize: 14, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          // RN sets buttonColor/primaryButtonColor to error2 here,
                          // so the CTA is the error role, not the brand primary.
                          backgroundColor: c.error,
                          foregroundColor: c.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: onDismiss,
                        child: PikdText('Retry', role: PikdTextRole.label, color: c.onPrimary),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onDismiss,
                      child: Text('Cancel', style: TextStyle(fontFamily: _themeFont(context), color: c.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
