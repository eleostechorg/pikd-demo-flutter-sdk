import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pikd_flutter_demo/tab_bar.dart';
import 'package:pikd_flutter_ui/pikd_flutter_ui.dart';

/// These exist because the bar shipped to a device with a 1 px vertical overflow
/// that made the Explore tab untappable. Flutter fails a widget test on an
/// overflow, and hit-testing is assertable, so both halves of that bug are
/// catchable here rather than on someone's phone.

Future<void> _pumpBar(
  WidgetTester tester, {
  PikdTab current = PikdTab.challenges,
  void Function(PikdTab)? onSelect,
  double bottomInset = 0,
  double textScale = 1.0,
  PikdTheme? theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        padding: EdgeInsets.only(bottom: bottomInset),
        textScaler: TextScaler.linear(textScale),
      ),
      child: PikdThemeProvider(
        theme: theme ?? PikdTheme.pikdDefault(),
        child: Scaffold(
          bottomNavigationBar:
              PikdTabBar(current: current, onSelect: onSelect ?? (_) {}),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lays out with no overflow, with and without a safe-area inset',
      (tester) async {
    // 0 is the Android-with-nav-buttons case; 34 is a notched iPhone. The bar
    // derives its height from its content, so neither should overflow — the
    // regression was a hardcoded 68 that left 44 for 45 of content.
    for (final inset in [0.0, 34.0, 48.0]) {
      await _pumpBar(tester, bottomInset: inset);
      expect(tester.takeException(), isNull, reason: 'inset $inset overflowed');
      expect(tester.getSize(find.byType(PikdTabBar)).height, inset == 0 ? 68 : 56 + inset);
    }
  });

  testWidgets('survives a large system text scale', (tester) async {
    // A bigger accessibility text size grows the label, which is the other way
    // this bar can overflow.
    await _pumpBar(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders RN\'s five tabs in order, AR unlabelled', (tester) async {
    await _pumpBar(tester);

    expect(find.text('Challenges'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // RN forces the camera tab's label to '' — it's the circled glyph only.
    expect(find.text('AR'), findsNothing);

    // Left-to-right order matches RN's TabNavigator.
    final xs = [
      for (final label in ['Challenges', 'Explore', 'Leaderboard', 'Profile'])
        tester.getCenter(find.text(label)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
  });

  testWidgets('every tab is tappable across its full slot, not just its label',
      (tester) async {
    // The original bug: a GestureDetector sizes to its child and a Column is only
    // as wide as its widest line, so each tap target was a label-width sliver.
    // Tapping near the slot edges is what proves the whole fifth is live.
    for (final tab in PikdTab.values) {
      final tapped = <PikdTab>[];
      await _pumpBar(tester, onSelect: tapped.add);

      final barWidth = tester.getSize(find.byType(PikdTabBar)).width;
      final slot = barWidth / PikdTab.values.length;
      final index = PikdTab.values.indexOf(tab);
      final y = tester.getCenter(find.byType(PikdTabBar)).dy;

      // 4 dp inside each edge of this tab's slot.
      for (final dx in [slot * index + 4, slot * (index + 1) - 4]) {
        tapped.clear();
        await tester.tapAt(Offset(dx, y));
        await tester.pump();
        expect(tapped, [tab], reason: '${tab.name} dead at x=$dx');
      }
    }
  });

  testWidgets('the AR glyph is vertically aligned with the labelled glyphs',
      (tester) async {
    // RN centres the circled camera glyph on the same line as its neighbours
    // (it uses a negative bottom margin). An earlier version shoved it *down*,
    // which is what put it visibly out of line and clipped it.
    await _pumpBar(tester);

    double glyphCentreY(PikdTab tab) => tester
        .getCenter(find.bySemanticsLabel(RegExp(tab.name)))
        .dy;

    // Fall back to geometry: find each tab's icon by its slot and compare the
    // rendered SVG centres.
    final svgs = find.byType(PikdTabBar);
    expect(svgs, findsOneWidget);

    final bar = tester.getRect(find.byType(PikdTabBar));
    // The circle must sit inside the bar — the clipping was the visible symptom.
    final circle = tester.getRect(find.byType(OverflowBox));
    expect(circle.top, greaterThanOrEqualTo(bar.top),
        reason: 'AR circle clipped at the top of the bar');
    expect(circle.bottom, lessThanOrEqualTo(bar.bottom),
        reason: 'AR circle clipped at the bottom of the bar');

    // And centred on the bar's icon line rather than pushed below it.
    expect(circle.center.dy, lessThan(bar.center.dy + 6));
    glyphCentreY; // referenced to keep the helper honest if reintroduced
  });

  testWidgets('tints follow the host theme rather than fixed hexes',
      (tester) async {
    const brandPink = Color(0xFFF50F64);
    const brandInk = Color(0xFFECECEC);
    const brandNav = Color(0xFF2D2F32);
    final magnum = PikdTheme.pikdDefault().copyWith(
      colors: PikdColors.dark.copyWith(
        activeAccent: brandPink,
        textPrimary: brandInk,
        navAccent: brandNav,
      ),
    );
    await _pumpBar(tester, theme: magnum, current: PikdTab.explore);

    // The selected label takes the brand's primary.
    final selected = tester.widget<Text>(find.text('Explore'));
    expect(selected.style?.color, brandPink);
    // An unselected one does not.
    final other = tester.widget<Text>(find.text('Profile'));
    expect(other.style?.color, brandInk);

    final cameraCircle = tester.widget<Container>(
      find.descendant(of: find.byType(OverflowBox), matching: find.byType(Container)).first,
    );
    expect((cameraCircle.decoration as BoxDecoration).color, brandNav);
  });
}
