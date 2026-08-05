import 'package:flutter/material.dart';
// Only the transport classes — the generated model types (FeedItem, Challenge,
// Comment…) collide by name with the module models, and the example uses the
// pikd_flutter_ui ones.
import 'package:pikd_flutter_api/api.dart'
    show
        ApiClient,
        LeaderboardApi,
        ProfileApi,
        FeedApi,
        ChallengesApi,
        CollectiblesApi;
import 'package:pikd_flutter_ui/pikd_flutter_ui.dart';

import 'explore_ar_collect_screen.dart';
import 'tab_bar.dart';
import 'geolocator_location_provider.dart';

/// Live config via `--dart-define`. **All four are required** — the app shows
/// [_MissingConfigScreen] rather than running, because there is no offline mode.
///
///   flutter run \
///     --dart-define=PIKD_BASE=https://HOST/api/sdk/v1 \
///     --dart-define=PIKD_SDK_KEY=pk_live_xxx \
///     --dart-define=PIKD_USER=HOST_USER_REF \
///     --dart-define=PIKD_LANGUAGE_REF=TENANT_LANGUAGE
///
/// [_user] is the host-side **userRef** (opaque to PIKD) — the server maps it to
/// the caller's PIKD identity, which is what the user-scoped modules (Profile,
/// Challenges, and the leaderboard's own-rank card) need.
///
/// The demo used to fall back to sample data whenever any of these was absent.
/// That made an unconfigured run look like a working product built on invented
/// data — and made it *slower* than the real thing, since the sample
/// repositories faked network latency. Both are gone.
const _base = String.fromEnvironment('PIKD_BASE');
const _key = String.fromEnvironment('PIKD_SDK_KEY');
const _user = String.fromEnvironment('PIKD_USER');
const _languageRef = String.fromEnvironment('PIKD_LANGUAGE_REF');

/// The production collect radius, in metres — how close you must be for a drop to
/// become collectible.
///
/// 5 m is the RN app's `FALLBACK_RADIUS` (`src/lib/utils/appConfig.ts`) and matches
/// what `PikdExploreMapView.collectRadiusMeters` already defaults to, so the demo
/// behaves exactly like production without any configuration.
///
/// Known, deliberate deferral: RN doesn't hardcode this — it fetches
/// `nearby_collect_radius_meters` from `GET app-config` (v5), caches it, and only
/// falls back to 5. `/sdk/v1` exposes no equivalent (verified: /app-config,
/// /config, /settings, /tenant all 404), so we pin the fallback. That's identical
/// behaviour while the server value is 5. The moment a tenant needs a different
/// radius, RN would follow it and we would not — at which point we need the
/// endpoint. There is no user-facing control for this in RN and none here.
const double kCollectRadiusDefault = 5;

/// Manrope type scale for the Magnum demo — mirrors the PIKD/Poppins ladder (same
/// sizes/weights, only the family changes). Per-role families are set explicitly
/// because PikdText paints `styleFor(role)` directly, so swapping only the
/// top-level `fontFamily` wouldn't reach the modules' text.
const PikdTypography kMagnumType = PikdTypography(
  fontFamily: 'Manrope',
  headingL: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 1.2,
  ),
  headingM: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.25,
  ),
  headingS: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
  ),
  title: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.3,
  ),
  body: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.4,
  ),
  bodyMuted: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  ),
  label: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
  ),
  caption: TextStyle(
    fontFamily: 'Manrope',
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.2,
  ),
);

/// Magnum — a real partner rebrand used as the demo's "test brand", mapped from
/// Magnum's brand sheet (Design System: Typography and colours). Toggling it
/// recolours and re-fonts every module. Neutrals use Magnum's exact values (dark
/// grey #2D2F32, mid grey #999999, light grey #ECECEC); accents come straight from
/// the numbered brand swatches; a couple of tints are derived (marked).
///
/// Font: Magnum's brand face is Cera Pro (commercial — not bundled). The demo
/// stands in **Manrope** (free, OFL-1.1; a geometric sans close in feel) via
/// [kMagnumType], so the rebrand shows a real font change. For the licensed Cera
/// Pro, drop its files in under family 'Cera Pro' and repoint [kMagnumType].
final PikdTheme kMagnumTheme = PikdTheme.pikdDefault().copyWith(
  colors: PikdColors.dark.copyWith(
    primary: const Color(0xFFF50F64), //         01 Magnum pink → CTAs / pills
    onPrimary: const Color(
      0xFFFFFFFF,
    ), //       white on pink (as Magnum's own CLUB lockup)
    activeAccent: const Color(
      0xFFFA91AF,
    ), //    09 light pink → active tab / badge / like
    primaryGradient: const [
      Color(0xFFF50F64),
      Color(0xFFD1004F),
    ], // 01 pink→deeper magenta; white hero content stays legible across it
    surfaceBrand: const Color(
      0xFFFA91AF,
    ), //    09 light pink → feed card / rank-1 tile
    onSurfaceBrand: const Color(0xFF2D2F32), //  dark-grey content on light pink
    background: const Color(
      0xFF0F0F10,
    ), //      near-black (Magnum black family)
    surface: const Color(0xFF1A1B1D),
    surfaceVariant: const Color(0xFF2D2F32), //  Magnum dark grey (exact)
    glass: const Color(
      0x802D2F32,
    ), //           neutral frosted (dark grey @ 50%)
    textSecondary: const Color(0xFF999999), //   Magnum mid grey (exact)
    textMuted: const Color(0xFF6E6E6E), //       derived dimmer grey
    onSurfaceInverse: const Color(0xFF2D2F32), // dark text on light tiles
    border: const Color(0xFF2D2F32), //          Magnum dark grey
    success: const Color(0xFF00C389), //         10 teal
    warning: const Color(0xFFFF8200), //         06 orange
    error: const Color(0xFFF9423A), //           11 warm red
    info: const Color(0xFF59CBE8), //            05 sky blue
    rank1: const Color(
      0xFFFA91AF,
    ), //           09 light pink → leaderboard top-3
    rank2: const Color(0xFFF9C0CE), //           derived paler pink
    rank3: const Color(0xFFECECEC), //           Magnum light grey (exact)
  ),
  typography: kMagnumType,
  // Header wordmark. Magnum's real lockup is artwork we don't have a licence to
  // bundle, so the name is rendered in their pink instead — enough to prove the
  // header rebrands, without inventing a logo.
  brandName: 'Magnum',
);

/// Demo toggle state — app-level (above the Navigator) so pushed detail routes
/// inherit it too.
final ValueNotifier<bool> rebrandOn = ValueNotifier<bool>(false);

/// How wide the demo *starts*. Deliberately 1 km rather than production's
/// [kCollectRadiusDefault], because 5 m makes the harness untestable indoors: the
/// staging drop sits tens of metres away (a gate, the next street), so the Collect
/// CTA correctly never appears and the flow can't be exercised at all.
///
/// This is a harness default, not a product change — the SDK's own default
/// (`PikdExploreMapView.collectRadiusMeters`) is still 5, so a tenant who passes
/// nothing gets production behaviour. Drop it back to 5 from the QA drawer to see
/// the real gating.
const double kDemoStartRadius = 1000;

/// The radius the Explore module is actually given. Moved only by the QA drawer —
/// it is a test affordance, not a setting a tenant's user would see.
final ValueNotifier<double> collectRadius = ValueNotifier<double>(
  kDemoStartRadius,
);

void main() => runApp(const PikdUiExampleApp());

class PikdUiExampleApp extends StatelessWidget {
  const PikdUiExampleApp({super.key});

  /// Every module here is LIVE against `/sdk/v1`. There is deliberately no
  /// sample-data fallback: a harness that silently swaps in fabricated rows when
  /// credentials are missing teaches a partner the wrong thing about the product,
  /// and it was doing exactly that. Missing config now fails loudly — see
  /// [_MissingConfigScreen].
  ///
  /// (`pikd_flutter_ui` still ships Sample* repositories as preview/test fixtures. They
  /// are for a consumer rendering a module before they have a key, not for this
  /// app.)
  static bool get isConfigured =>
      _base.isNotEmpty &&
      _key.isNotEmpty &&
      _user.isNotEmpty &&
      _languageRef.isNotEmpty;

  /// What's missing, for the config screen to name precisely.
  static List<String> get missingConfig => [
    if (_base.isEmpty) 'PIKD_BASE',
    if (_key.isEmpty) 'PIKD_SDK_KEY',
    if (_user.isEmpty) 'PIKD_USER',
    if (_languageRef.isEmpty) 'PIKD_LANGUAGE_REF',
  ];

  /// Builds an `/sdk/v1` client (base + sdk-key header). Only ever called once
  /// [isConfigured] holds, so it can't hand back a half-configured client.
  static ApiClient _liveClient() {
    final client = ApiClient(basePath: _base);
    client.addDefaultHeader('x-pikd-sdk-key', _key);
    return client;
  }

  static LeaderboardRepository buildLeaderboardRepository() =>
      PikdSdkLeaderboardRepository(
        LeaderboardApi(_liveClient()),
        userRef: _user,
      );

  static ProfileRepository buildProfileRepository() =>
      PikdSdkProfileRepository(ProfileApi(_liveClient()), userRef: _user);

  // Feed is deliberately not surfaced (in the RN app it's the News tab's second
  // local tab; we were asked to drop it). The module still ships and works — this
  // builder is the reference for wiring it live in a host app.
  static FeedRepository buildFeedRepository() =>
      PikdSdkFeedRepository(FeedApi(_liveClient()), userRef: _user);

  static ChallengeRepository buildChallengeRepository() =>
      PikdSdkChallengeRepository(ChallengesApi(_liveClient()), userRef: _user);

  static PikdSdkExploreRepository buildExploreRepository() =>
      PikdSdkExploreRepository(
        CollectiblesApi(_liveClient()),
        languageRef: _languageRef,
        xPikdUser: _user,
      );

  /// Real device GPS. There's no fixed-location fallback either — a map centred on
  /// a hardcoded city is the same lie as fake rows.
  static ExploreLocationProvider buildExploreLocationProvider() =>
      GeolocatorExploreLocationProvider();

  @override
  Widget build(BuildContext context) {
    // One PikdTheme drives BOTH the Material theme (the scaffold/app-bar/nav
    // chrome this demo owns) and the PikdThemeProvider the modules read. Keeping
    // them on the same source means the brand toggle repaints the whole app —
    // otherwise the frame around every tab stays PIKD-dark while the module
    // bodies turn Magnum, which reads as a themeability gap rather than a demo
    // shortcut. A host should wire its own chrome the same way.
    return ValueListenableBuilder<bool>(
      valueListenable: rebrandOn,
      builder: (context, on, _) {
        final pikd = on ? kMagnumTheme : PikdTheme.pikdDefault();
        return MaterialApp(
          title: 'PIKD UI Example',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(
            useMaterial3: true,
          ).copyWith(scaffoldBackgroundColor: pikd.colors.background),
          // Provide PikdTheme ABOVE the Navigator so pushed detail routes
          // (challenge detail, feed comments, asset detail…) inherit it too — a
          // host should do the same (e.g. MaterialApp.builder) rather than
          // wrapping one screen.
          builder: (context, child) =>
              PikdThemeProvider(theme: pikd, child: child!),
          // Fail loudly rather than falling back to fabricated data.
          home: isConfigured
              ? const _HomeShell()
              : const _MissingConfigScreen(),
        );
      },
    );
  }
}

/// Demo shell. Tab order, glyphs, labels and chrome follow the RN app's
/// `TabNavigator`: Challenges (RN's News slot) → Explore → AR → Leaderboard →
/// Profile, with the AR tab unlabelled inside a circle and the bar hidden
/// outright while AR is on screen.
class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  PikdTab _current = PikdTab.challenges;

  /// Tabs are built lazily: an IndexedStack builds *every* child up front, and
  /// the Explore tab's Google Map is expensive enough that doing so stalls the
  /// first paint and makes tab switches feel stuck. We keep IndexedStack (so a
  /// visited tab holds its state) but only materialise tabs once visited.
  final Set<PikdTab> _visited = {PikdTab.challenges};

  Widget _screen(PikdTab t) => switch (t) {
    PikdTab.challenges => const _ChallengesScreen(),
    PikdTab.explore => const _ExploreScreen(),
    PikdTab.ar => _ArScreen(onExitToTab: _select),
    PikdTab.leaderboard => const _LeaderboardScreen(),
    PikdTab.profile => const _ProfileScreen(),
  };

  void _select(PikdTab t) => setState(() {
    // Google Maps is another GPU-heavy Android PlatformView. Never keep it
    // mounted behind SceneView: doing so creates two native renderers plus
    // Flutter's compositor in one window and causes severe startup/frame
    // contention on mid-range devices. Recreate Explore when the user next
    // opens it instead of preserving a hidden live map during AR.
    if (t == PikdTab.ar && _current != PikdTab.ar) {
      _visited.remove(PikdTab.explore);
    }

    // Leaving AR evicts it, which is what actually stops the camera. An
    // IndexedStack keeps every visited child mounted, so the AR screen would
    // otherwise sit alive behind whatever tab you switched to — camera and
    // ARKit/ARCore session still running — and because it was never disposed,
    // coming back wouldn't re-run its setup either, so you'd return to a stale
    // screen. Dropping it from [_visited] disposes the subtree, which fires the
    // teardown it already has (clear scene -> clear cache -> stop session) and
    // guarantees a fresh start on re-entry.
    //
    // RN reaches the same outcome differently: it runs a controlled AR close
    // before navigating away, and gates on `useIsFocused`.
    if (_current == PikdTab.ar && t != PikdTab.ar) _visited.remove(PikdTab.ar);
    _current = t;
    _visited.add(t);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _QaDrawer(),
      body: IndexedStack(
        index: PikdTab.values.indexOf(_current),
        children: [
          for (final t in PikdTab.values)
            _visited.contains(t) ? _screen(t) : const SizedBox.shrink(),
        ],
      ),
      // RN hides the tab bar entirely on the camera route (its `renderTabBar`
      // returns null for SCREENS.CAMERA) so the AR view is full-bleed.
      bottomNavigationBar: _current == PikdTab.ar
          ? null
          : PikdTabBar(current: _current, onSelect: _select),
    );
  }
}

/// Everything demo-only lives here, behind the header's hamburger — the same slot
/// the RN app uses for app-level navigation. Keeping it off the header means the
/// header itself is identical to production: a real user of a tenant's app would
/// never see a brand switcher or a radius override.
class _QaDrawer extends StatelessWidget {
  const _QaDrawer();

  @override
  Widget build(BuildContext context) {
    final t = PikdThemeProvider.of(context);
    final c = t.colors;
    TextStyle style(
      double size,
      Color color, [
      FontWeight w = FontWeight.w400,
    ]) => TextStyle(
      fontFamily: t.typography.fontFamily,
      fontSize: size,
      fontWeight: w,
      color: color,
    );

    return Drawer(
      backgroundColor: c.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                'QA CONTROLS',
                style: style(11, c.textMuted, FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Demo harness only — none of this ships in the SDK.',
                style: style(12, c.textSecondary),
              ),
            ),
            Divider(color: c.border, height: 1),

            // Data source. There is only one now - live - so this states the base
            // URL and user rather than which of two modes we're in.
            ListTile(
              leading: Icon(
                Icons.cloud_done_outlined,
                color: c.success,
                size: 20,
              ),
              title: Text(
                'Data source',
                style: style(14, c.textPrimary, FontWeight.w600),
              ),
              subtitle: Text(
                'live - $_base\nuser: $_user',
                style: style(12, c.textSecondary),
              ),
            ),
            Divider(color: c.border, height: 1),

            // Brand toggle: the whole point of a white-label SDK demo.
            ValueListenableBuilder<bool>(
              valueListenable: rebrandOn,
              builder: (_, on, _) => SwitchListTile(
                value: on,
                onChanged: (v) => rebrandOn.value = v,
                activeThumbColor: c.primary,
                title: Text(
                  'Rebrand',
                  style: style(14, c.textPrimary, FontWeight.w600),
                ),
                subtitle: Text(
                  on ? 'Magnum' : 'PIKD (default)',
                  style: style(12, c.textSecondary),
                ),
                secondary: Icon(
                  on ? Icons.palette : Icons.palette_outlined,
                  color: c.primary,
                  size: 20,
                ),
              ),
            ),
            Divider(color: c.border, height: 1),

            // Collect radius. Production is a fixed 5 m (see kCollectRadiusDefault),
            // so this is strictly a test affordance: without it a tester has to stand
            // within 5 m of a drop. The RN app has the same idea in its filter sheet,
            // gated to tester accounts ("Test Range").
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text(
                'Collect radius',
                style: style(14, c.textPrimary, FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Production is ${kCollectRadiusDefault.toStringAsFixed(0)} m; this demo starts at '
                '${(kDemoStartRadius / 1000).toStringAsFixed(0)} km so a drop is reachable indoors. '
                'Capped at 5 km, the nearby facade\'s own limit.',
                style: style(12, c.textSecondary),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: collectRadius,
              // RadioGroup rather than per-tile groupValue/onChanged: those were
              // deprecated after Flutter 3.32 and Magnum may well be on a newer
              // stable than ours, so the demo shouldn't ship deprecation noise.
              builder: (_, cur, _) => RadioGroup<double>(
                groupValue: cur,
                onChanged: (v) => collectRadius.value = v ?? kDemoStartRadius,
                child: Column(
                  children: [
                    for (final m in const [
                      kCollectRadiusDefault,
                      100.0,
                      kDemoStartRadius,
                      5000.0,
                    ])
                      RadioListTile<double>(
                        value: m,
                        activeColor: c.primary,
                        dense: true,
                        title: Text(
                          '${m >= 1000 ? "${(m / 1000).toStringAsFixed(0)} km" : "${m.toStringAsFixed(0)} m"}'
                          '${m == kCollectRadiusDefault ? "  (production)" : ""}'
                          '${m == kDemoStartRadius ? "  (demo default)" : ""}',
                          style: style(13, c.textPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared page header, mirroring the RN app's tab header
/// (`src/components/layouts/Screen.tsx`, `hasHeader`): 62 dp tall, hamburger left,
/// brand centre, notification bell right.
///
/// RN centres its logo asset. We render [PikdTheme.brandName] as a wordmark
/// instead — "PIKD", or "Magnum" in Magnum's pink once the brand is toggled — so
/// the header rebrands without a per-tenant asset pipeline.
///
/// Deliberately takes no title/subtitle: the previous version showed
/// "PIKD • Leaderboard" over a "sample data (offline)" line, which exists nowhere
/// in production. Everything demo-specific now lives behind the hamburger, in
/// [_QaDrawer].
PreferredSizeWidget _demoAppBar(BuildContext context) => const _RnHeader();

class _RnHeader extends StatelessWidget implements PreferredSizeWidget {
  const _RnHeader();

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    final t = PikdThemeProvider.of(context);
    final c = t.colors;
    return Material(
      color: c.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              // RN: hamburger, 25 dp, marginLeft 16 / pr 28, toggles the drawer.
              GestureDetector(
                onTap: () => Scaffold.of(context).openDrawer(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, right: 28),
                  child: Icon(Icons.menu, size: 25, color: c.textPrimary),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    t.brandName,
                    style: TextStyle(
                      fontFamily: t.typography.fontFamily,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: c.primary,
                    ),
                  ),
                ),
              ),
              // RN's bell routes to a Notifications screen. There's no
              // notifications module here, so it answers honestly via a toast
              // rather than being a dead control.
              GestureDetector(
                onTap: () => PikdToast.show(
                  context,
                  type: PikdToastType.info,
                  title: 'Nothing new',
                  description:
                      "You're all caught up — we'll ping you when a drop lands nearby.",
                ),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 28, right: 16),
                  child: Icon(
                    Icons.notifications_none,
                    size: 25,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tab 1. In the RN app this is the News tab's first local tab; here it's the tab
/// itself. The detail view carries its own Leaderboard tab, which is where the
/// challenge-scoped board (`GET /leaderboard/{challengeId}`) surfaces — so the
/// live leaderboard repository has to be passed in, not left on the sample default.
class _ChallengesScreen extends StatelessWidget {
  const _ChallengesScreen();

  @override
  Widget build(BuildContext context) {
    final repo = PikdUiExampleApp.buildChallengeRepository();
    return Scaffold(
      drawer: const _QaDrawer(),
      appBar: _demoAppBar(context),
      body: PikdChallengesView(
        repository: repo,
        onOpenChallenge: (c) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (detailCtx) => Scaffold(
              body: SafeArea(
                bottom: false,
                child: PikdChallengeDetailView(
                  repository: repo,
                  challengeId: c.id,
                  onBack: () => Navigator.of(detailCtx).pop(),
                  onOpenComments: () => PikdToast.show(
                    context,
                    type: PikdToastType.info,
                    title: 'Discussion',
                    description: c.name,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeaderboardScreen extends StatefulWidget {
  const _LeaderboardScreen();

  @override
  State<_LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<_LeaderboardScreen> {
  String? _challengeId;
  String? _challengeName;

  Future<void> _pickChallenge() async {
    final theme = PikdThemeProvider.of(context);
    final result = await showModalBottomSheet<({String id, String name})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: theme.colors.overlay,
      builder: (_) => PikdThemeProvider(
        theme: theme,
        child: _ChallengePickerSheet(
          api: ChallengesApi(PikdUiExampleApp._liveClient()),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _challengeId = result.id;
        _challengeName = result.name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _QaDrawer(),
      appBar: _demoAppBar(context),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _LeaderboardChallengePill(
              name: _challengeName,
              onTap: _pickChallenge,
              onClear: _challengeId != null
                  ? () => setState(() {
                        _challengeId = null;
                        _challengeName = null;
                      })
                  : null,
            ),
          ),
          Expanded(
            child: PikdLeaderboardView(
              repository: PikdUiExampleApp.buildLeaderboardRepository(),
              limit: 25,
              challengeId: _challengeId,
            ),
          ),
        ],
      ),
    );
  }
}

/// Challenge filter pill for the leaderboard screen — mirrors the explore
/// ChallengeSelector pill: layers icon + name/placeholder + chevron, with a
/// clear button when active.
class _LeaderboardChallengePill extends StatelessWidget {
  final String? name;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _LeaderboardChallengePill({
    required this.onTap,
    this.name,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = PikdThemeProvider.of(context);
    final active = name != null;
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: active ? theme.colors.surfaceVariant : theme.colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? theme.colors.activeAccent : theme.colors.border,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 18,
                    color: active ? theme.colors.activeAccent : theme.colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PikdText(
                      name ?? 'All challenges',
                      role: PikdTextRole.label,
                      color: theme.colors.textPrimary,
                      maxLines: 1,
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, size: 16,
                      color: theme.colors.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (active && onClear != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colors.surfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colors.border),
              ),
              child: Icon(Icons.close, size: 16, color: theme.colors.textPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

/// 80%-height bottom sheet that lists all challenges from the API and returns
/// the tapped one — mirrors [showExploreChallengeModal] from the explore module.
class _ChallengePickerSheet extends StatefulWidget {
  final ChallengesApi api;
  const _ChallengePickerSheet({required this.api});

  @override
  State<_ChallengePickerSheet> createState() => _ChallengePickerSheetState();
}

class _ChallengePickerSheetState extends State<_ChallengePickerSheet> {
  bool _loading = true;
  List<({String id, String name})> _challenges = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.api.getChallenges();
      if (mounted) {
        setState(() => _challenges = [
              for (final c in raw ?? [])
                if (c.name?.trim().isNotEmpty ?? false)
                  (id: c.id, name: c.name!.trim()),
            ]);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = PikdThemeProvider.of(context);
    return FractionallySizedBox(
      heightFactor: 0.8,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: theme.colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PikdText('Choose challenge',
                  role: PikdTextRole.headingM,
                  color: theme.colors.textPrimary),
            ),
            Divider(color: theme.colors.border, height: 1),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: theme.colors.primary))
                  : _challenges.isEmpty
                      ? Center(
                          child: PikdText('No challenges available',
                              role: PikdTextRole.body,
                              color: theme.colors.textSecondary))
                      : ListView.separated(
                          itemCount: _challenges.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: theme.colors.border, height: 1),
                          itemBuilder: (_, i) {
                            final c = _challenges[i];
                            return GestureDetector(
                              onTap: () => Navigator.of(context).pop(c),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                child: PikdText(c.name,
                                    role: PikdTextRole.body,
                                    color: theme.colors.textPrimary,
                                    maxLines: 1),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final repo = PikdUiExampleApp.buildProfileRepository();
    return Scaffold(
      drawer: const _QaDrawer(),
      appBar: _demoAppBar(context),
      body: PikdProfileView(
        repository: repo,
        // Tile tap → collection drill-down → asset detail → View-in-AR.
        onOpenCollection: (item) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (collCtx) => Scaffold(
              body: SafeArea(
                child: PikdCollectionListView(
                  repository: repo,
                  collectionId: item.id,
                  onBack: () => Navigator.of(collCtx).pop(),
                  onOpenAsset: (asset) => Navigator.of(collCtx).push(
                    MaterialPageRoute<void>(
                      builder: (assetCtx) => Scaffold(
                        body: SafeArea(
                          child: PikdAssetDetailView(
                            asset: asset,
                            onClose: () => Navigator.of(assetCtx).pop(),
                            onViewInAR: (a) {
                              Navigator.of(assetCtx).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ExploreArCollectScreen(
                                    collectible: ExploreCollectible(
                                      id: a.id,
                                      latitude: 0,
                                      longitude: 0,
                                      name: a.name,
                                      imageUrl: a.imageUrl,
                                      points: a.points,
                                      assetModelUrlIos: a.modelUrlIos,
                                      assetModelUrlAndroid: a.modelUrlAndroid,
                                    ),
                                    base: _base,
                                    sdkKey: _key,
                                    userRef: _user,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExploreScreen extends StatefulWidget {
  const _ExploreScreen();

  @override
  State<_ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<_ExploreScreen> {
  bool _arRouteOpen = false;

  Future<void> _openCollectAr(ExploreCollectible collectible) async {
    if (_arRouteOpen) return;

    // Dispose GoogleMap before mounting SceneView. Keeping both platform views
    // alive makes AR startup contend for the UI thread, GPU, and camera-frame
    // scheduling. Waiting one frame ensures the map's native view is detached
    // before the AR route begins building.
    setState(() => _arRouteOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExploreArCollectScreen(
            collectible: collectible,
            base: _base,
            sdkKey: _key,
            userRef: _user,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _arRouteOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _QaDrawer(),
      appBar: _demoAppBar(context),
      body: _arRouteOpen
          ? ColoredBox(color: PikdThemeProvider.of(context).colors.background)
          : ValueListenableBuilder<double>(
              valueListenable: collectRadius,
              builder: (context, radius, _) => PikdExploreMapView(
                repository: PikdUiExampleApp.buildExploreRepository(),
                locationProvider:
                    PikdUiExampleApp.buildExploreLocationProvider(),
                collectRadiusMeters:
                    radius, // production default; only the QA drawer moves it
                // Explore → AR collect hand-off. No live-mode guard needed: the app won't
                // reach a tab unless it's configured (see [_MissingConfigScreen]). AR still
                // needs a physical device for ARKit/ARCore.
                onCollect: _openCollectAr,
                onNavigateAr: (c) => PikdToast.show(
                  context,
                  type: PikdToastType.info,
                  title: 'Navigate in AR',
                  description: c.name,
                ),
                onOpenExternalMap: (lat, lng) => PikdToast.show(
                  context,
                  type: PikdToastType.info,
                  title: 'Open maps',
                  description:
                      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                ),
              ),
            ),
    );
  }
}

/// AR tab — the SAME camera screen the Explore Collect CTA opens, just without a
/// pinned asset, so it places everything nearby. RN works exactly this way: its
/// MarkerDetailCard navigates to SCREENS.CAMERA with `{ assetId }`, which the
/// camera screen holds as `pinnedAssetId`; opened directly there's no param, so it
/// shows all nearby assets.
class _ArScreen extends StatelessWidget {
  const _ArScreen({required this.onExitToTab});

  /// Where the screen's X (and "Go to profile") should land. As a tab there is no
  /// route to pop, so without this the close button blanked the app. RN does the
  /// same thing — its close handler navigates to `returnToTab || SCREENS.NEWS`
  /// rather than popping.
  final void Function(PikdTab) onExitToTab;

  @override
  Widget build(BuildContext context) {
    // Unpinned: no `collectible`, so the screen fetches nearby itself via the same
    // repository the Explore map uses. No config guard — the app can't reach a tab
    // unconfigured. A simulator will still fail at the ARKit/ARCore layer, which
    // the screen surfaces itself.
    return ExploreArCollectScreen(
      base: _base,
      sdkKey: _key,
      userRef: _user,
      // RN falls back to its News tab; ours is Challenges in that slot.
      onClose: () => onExitToTab(PikdTab.challenges),
      onViewProfile: () => onExitToTab(PikdTab.profile),
      nearbySource: () async {
        final repo = PikdUiExampleApp.buildExploreRepository();
        final here = await PikdUiExampleApp.buildExploreLocationProvider()
            .getCurrentLocation();
        // Not an empty result: an empty list would tell the AR screen there is
        // nothing nearby, which is a claim we cannot make without a position.
        if (here == null) throw const LocationUnavailableException();
        return repo.fetchArNearby(
          latitude: here.latitude,
          longitude: here.longitude,
          radiusMeters: collectRadius.value.round(),
          limit: 8,
        );
      },
    );
  }
}

/// Shown instead of the app when `--dart-define` config is missing.
///
/// This replaces what used to happen: every repository quietly swapped in a
/// Sample* implementation, so an unconfigured run looked like a working app full
/// of invented people and drops. A partner evaluating the SDK could easily have
/// mistaken that for the product — and it was slower than the real thing, because
/// the sample repositories faked network latency.
class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    final t = PikdThemeProvider.of(context);
    final c = t.colors;
    TextStyle style(
      double size,
      Color color, [
      FontWeight w = FontWeight.w400,
    ]) => TextStyle(
      fontFamily: t.typography.fontFamily,
      fontSize: size,
      fontWeight: w,
      color: color,
      height: 1.45,
    );

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.key_off_outlined, size: 44, color: c.warning),
                const SizedBox(height: 20),
                Text(
                  'Configuration required',
                  style: style(22, c.textPrimary, FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  'This demo runs against live /sdk/v1 only — it has no offline mode, '
                  'so nothing you see here is ever fabricated.',
                  style: style(14, c.textSecondary),
                ),
                const SizedBox(height: 20),
                Text(
                  'Missing:',
                  style: style(13, c.textPrimary, FontWeight.w600),
                ),
                const SizedBox(height: 6),
                for (final key in PikdUiExampleApp.missingConfig)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '  •  $key',
                      style: style(13, c.error, FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    'flutter run \\\n'
                    '  --dart-define=PIKD_BASE=https://HOST/api/sdk/v1 \\\n'
                    '  --dart-define=PIKD_SDK_KEY=pk_live_xxx \\\n'
                    '  --dart-define=PIKD_USER=YOUR_USER_REF \\\n'
                    '  --dart-define=PIKD_LANGUAGE_REF=TENANT_LANGUAGE',
                    style: style(
                      12,
                      c.textSecondary,
                    ).copyWith(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your SDK key scopes every call to your tenant. See demo/README.md.',
                  style: style(12, c.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
