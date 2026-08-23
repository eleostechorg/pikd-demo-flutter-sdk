import 'package:flutter/material.dart';
import 'package:pikd_flutter_experience/pikd_flutter_experience.dart';

/// Local values are supplied with `--dart-define-from-file`. The demo does not
/// contain a fallback tenant or fabricated data, so an incomplete setup is
/// always visible instead of looking like a working PIKD integration.
const _baseUrl = String.fromEnvironment('PIKD_BASE');
const _sdkKey = String.fromEnvironment('PIKD_SDK_KEY');
const _userRef = String.fromEnvironment('PIKD_USER');
// `PIKD_LANGUAGE_REF` is retained only as a local-demo compatibility bridge
// while existing developers move to the explicit UI/content settings below.
const _legacyLanguageRef = String.fromEnvironment('PIKD_LANGUAGE_REF');
const _contentLanguageRef = String.fromEnvironment(
  'PIKD_CONTENT_LANGUAGE_REF',
  defaultValue: _legacyLanguageRef,
);
const _uiLocaleValue = String.fromEnvironment(
  'PIKD_UI_LOCALE',
  defaultValue: _legacyLanguageRef,
);
final _uiLocale = PikdLocale.tryParse(_uiLocaleValue);
const _collectRadiusMetersValue = String.fromEnvironment(
  'PIKD_DEMO_COLLECT_RADIUS_M',
);
final _collectRadiusMeters = double.tryParse(_collectRadiusMetersValue) ?? 5;

/// Magnum's published palette. Cera Pro is commercially licensed and is not
/// redistributed here, so this demo uses the SDK's bundled OFL-licensed
/// Manrope fallback. A host that licenses Cera Pro can replace the family name
/// with `PikdTypography.poppins.withFontFamily('Cera Pro')`.
final _magnumTheme = PikdTheme.pikdDefault().copyWith(
  colors: PikdColors.dark.copyWith(
    primary: const Color(0xFFF50F64),
    onPrimary: const Color(0xFFFFFFFF),
    activeAccent: const Color(0xFFFA91AF),
    primaryGradient: const [Color(0xFFF50F64), Color(0xFFD1004F)],
    surfaceBrand: const Color(0xFFFA91AF),
    onSurfaceBrand: const Color(0xFF2D2F32),
    background: const Color(0xFF0F0F10),
    surface: const Color(0xFF1A1B1D),
    surfaceVariant: const Color(0xFF2D2F32),
    glass: const Color(0x802D2F32),
    navAccent: const Color(0xFF2D2F32),
    mapSurface: const Color(0xCCFFFFFF),
    onMapSurface: const Color(0xFF2D2F32),
    textSecondary: const Color(0xFF999999),
    textMuted: const Color(0xFF6E6E6E),
    onSurfaceInverse: const Color(0xFF2D2F32),
    border: const Color(0xFF2D2F32),
    success: const Color(0xFF00C387),
    warning: const Color(0xFFFF8200),
    error: const Color(0xFFF9423A),
    info: const Color(0xFF59CBE8),
    rank1: const Color(0xFFFA91AF),
    rank2: const Color(0xFFF9C0CE),
    rank3: const Color(0xFFECECEC),
  ),
  typography: PikdTypography.poppins.withFontFamily('Manrope'),
  brandName: 'Magnum',
);

/// Copy owned by this host-app demo. The PIKD and Magnum brand names remain
/// unchanged; the surrounding launch UI follows the locale passed to the PIKD
/// experience.
class _DemoStrings {
  const _DemoStrings({
    required this.appTitle,
    required this.discoverNearby,
    required this.experienceDescription,
    required this.openPikd,
    required this.configurationRequired,
    required this.configurationDescription,
  });

  final String appTitle;
  final String discoverNearby;
  final String experienceDescription;
  final String openPikd;
  final String configurationRequired;
  final String configurationDescription;

  static _DemoStrings forLocale(PikdLocale? locale) => switch (locale) {
    PikdLocale.russian => const _DemoStrings(
      appTitle: 'Демонстрация Flutter-опыта PIKD',
      discoverNearby: 'Откройте коллекционные предметы рядом с вами',
      experienceDescription:
          'Откройте полный опыт PIKD: Исследование, сбор в AR, таблица лидеров и профиль.',
      openPikd: 'Открыть PIKD',
      configurationRequired: 'Требуется настройка',
      configurationDescription:
          'Скопируйте config/pikd.example.json в config/pikd.local.json и укажите:',
    ),
    PikdLocale.kazakh => const _DemoStrings(
      appTitle: 'Демо Flutter тәжірибесі PIKD',
      discoverNearby: 'Жақын маңдағы коллекциялық заттарды табыңыз',
      experienceDescription:
          'PIKD-тің толық тәжірибесін ашыңыз: зерттеу, AR арқылы жинау, көшбасшылар тақтасы және профиль.',
      openPikd: 'PIKD ашу',
      configurationRequired: 'Конфигурация қажет',
      configurationDescription:
          'config/pikd.example.json файлын config/pikd.local.json ретінде көшіріп, мыналарды толтырыңыз:',
    ),
    _ => const _DemoStrings(
      appTitle: 'PIKD Flutter experience demo',
      discoverNearby: 'Discover collectibles around you',
      experienceDescription:
          'Open the complete PIKD experience: Explore, AR Collect, leaderboard, and profile.',
      openPikd: 'Open PIKD',
      configurationRequired: 'Configuration required',
      configurationDescription:
          'Copy config/pikd.example.json to config/pikd.local.json and provide:',
    ),
  };
}

void main() => runApp(const PikdExperienceDemoApp());

class PikdExperienceDemoApp extends StatelessWidget {
  const PikdExperienceDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: _DemoStrings.forLocale(_uiLocale).appTitle,
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const _DemoHome(),
  );
}

class _DemoHome extends StatelessWidget {
  const _DemoHome();

  List<String> get _missing => [
    if (_baseUrl.trim().isEmpty) 'PIKD_BASE',
    if (_sdkKey.trim().isEmpty) 'PIKD_SDK_KEY',
    if (_userRef.trim().isEmpty) 'PIKD_USER',
    if (_contentLanguageRef.trim().isEmpty) 'PIKD_CONTENT_LANGUAGE_REF',
    if (_uiLocale == null) 'PIKD_UI_LOCALE (ru or kk)',
  ];

  Future<void> _open(BuildContext context) => PikdFlutterExperience.open(
    context,
    configuration: PikdFlutterExperienceConfiguration(
      baseUrl: _baseUrl,
      sdkKey: _sdkKey,
      userRef: _userRef,
      locale: _uiLocale ?? PikdLocale.russian,
      contentLanguageRef: _contentLanguageRef,
      collectRadiusMeters: _collectRadiusMeters,
      theme: _magnumTheme,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final strings = _DemoStrings.forLocale(_uiLocale);
    return Scaffold(
      backgroundColor: _magnumTheme.colors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: missing.isNotEmpty
                  ? _MissingConfiguration(values: missing, strings: strings)
                  : _PikdLaunchCard(
                      onOpen: () => _open(context),
                      strings: strings,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PikdLaunchCard extends StatelessWidget {
  const _PikdLaunchCard({required this.onOpen, required this.strings});

  final VoidCallback onOpen;
  final _DemoStrings strings;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _magnumTheme.colors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _magnumTheme.colors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'magnum club',
            style: TextStyle(
              color: _magnumTheme.colors.primary,
              fontFamily: _magnumTheme.typography.fontFamily,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            strings.discoverNearby,
            style: _magnumTheme.typography.headingL.copyWith(
              color: _magnumTheme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.experienceDescription,
            style: _magnumTheme.typography.body.copyWith(
              color: _magnumTheme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.explore_outlined),
              label: Text(strings.openPikd),
              style: FilledButton.styleFrom(
                backgroundColor: _magnumTheme.colors.primary,
                foregroundColor: _magnumTheme.colors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: _magnumTheme.typography.title,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MissingConfiguration extends StatelessWidget {
  const _MissingConfiguration({required this.values, required this.strings});

  final List<String> values;
  final _DemoStrings strings;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _magnumTheme.colors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _magnumTheme.colors.warning),
    ),
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.settings_outlined,
            color: _magnumTheme.colors.warning,
            size: 32,
          ),
          const SizedBox(height: 16),
          Text(
            strings.configurationRequired,
            style: _magnumTheme.typography.headingL.copyWith(
              color: _magnumTheme.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.configurationDescription,
            style: _magnumTheme.typography.body.copyWith(
              color: _magnumTheme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $value',
                style: _magnumTheme.typography.body.copyWith(
                  color: _magnumTheme.colors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
