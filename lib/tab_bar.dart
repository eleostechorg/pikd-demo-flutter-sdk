import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pikd_flutter_ui/pikd_flutter_ui.dart';

/// One entry in the bottom bar. Mirrors the RN app's tab set
/// (`src/navigators/TabNavigator.tsx`) slot for slot.
enum PikdTab {
  /// RN's News slot. In RN, Challenges is News's first local tab; here it *is*
  /// the tab (Feed and Communities are out of scope), so it keeps RN's News glyph
  /// — the slot stays visually identical to production — with an honest label.
  challenges('Challenges', 'challenges'),
  explore('Explore', 'explore'),

  /// RN gives the camera tab NO label and sets its icon in a grey circle.
  ar(null, 'ar'),
  leaderboard('Leaderboard', 'leaderboard'),
  profile('Profile', 'profile');

  const PikdTab(this.label, this.slug);

  /// Null = render no label (RN forces `tabBarLabel: ''` for Camera).
  final String? label;
  final String slug;

  String get icon => 'assets/icons/tab-$slug.svg';
  String get activeIcon => 'assets/icons/tab-$slug-active.svg';
}

/// The bottom bar, hand-built rather than a Material [NavigationBar] because RN's
/// shape can't be expressed with one: a tab with no label, a tab whose icon sits
/// in a raised circle, and RN's own metrics (25 dp glyphs, 10 dp semibold labels,
/// `insets.bottom + 56` height).
class PikdTabBar extends StatelessWidget {
  const PikdTabBar({super.key, required this.current, required this.onSelect});

  final PikdTab current;
  final void Function(PikdTab) onSelect;

  @override
  Widget build(BuildContext context) {
    final c = PikdThemeProvider.of(context).colors;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // RN's metrics are exactly 68 without an inset and 56 + the safe-area inset
    // otherwise. The fixed 44 dp content row keeps those metrics overflow-safe.
    const padTop = 12.0;
    final padBottom = bottomInset > 0 ? bottomInset : 12.0;
    // Material wrapper suppresses any M3 elevation surface-tint the Scaffold
    // would apply to the bottomNavigationBar slot, keeping the bar surface
    // exactly c.surface with no tinting or overlay artefacts.
    // DecoratedBox paints only — it does NOT add to the Padding's insets the
    // way Container._paddingIncludingDecoration does, so the 1 dp border width
    // no longer eats into the 44 dp content row and the overflow is gone.
    return Material(
      color: c.surface,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        child: SizedBox(
          height: padTop + _PikdTabItem.contentHeight + padBottom,
          child: Padding(
            padding: EdgeInsets.only(top: padTop, bottom: padBottom),
            child: Row(
              children: [
                for (final t in PikdTab.values)
                  Expanded(
                    child: _PikdTabItem(
                      tab: t,
                      selected: t == current,
                      onTap: () => onSelect(t),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PikdTabItem extends StatelessWidget {
  const _PikdTabItem({required this.tab, required this.selected, required this.onTap});

  /// Every tab uses the SAME vertical structure — a fixed icon row, a gap, a fixed
  /// label row — so the icons line up by construction rather than by a nudge.
  /// An earlier version centred each tab's own column and then shoved the circle
  /// with a Transform, which both mis-aligned it and overflowed the bar by 1 px.
  static const double _iconRow = 25;
  static const double _gap = 4;
  static const double _labelRow = 15;
  static const double _circle = 45;

  /// Total content the bar must accommodate.
  static const double contentHeight = _iconRow + _gap + _labelRow; // 44

  final PikdTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = PikdThemeProvider.of(context);
    final c = theme.colors;
    // Semantic theme roles keep the whole bar partner-brandable. The focused
    // glyph is also filled, so state does not rely on colour alone.
    final tint = selected ? c.activeAccent : c.textPrimary;
    final glyph = SvgPicture.asset(
      selected ? tab.activeIcon : tab.icon,
      width: _iconRow,
      height: _iconRow,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );

    return GestureDetector(
      onTap: onTap,
      // opaque alone isn't enough: a GestureDetector sizes to its child, and a
      // Column only as wide as its widest line — so the tappable area was a
      // label-width sliver instead of the whole fifth of the bar. Filling the slot
      // is what makes the full tab hittable.
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: _iconRow,
              child: Center(
                child: tab.label == null
                    // RN's camera tab: the glyph in a grey circle. An OverflowBox
                    // lets the 45 dp circle render centred on the 25 dp icon line
                    // without taking 45 dp of layout — which is what keeps it
                    // aligned with the neighbouring glyphs (RN gets there with a
                    // negative bottom margin) and keeps it inside the bar.
                    ? Transform.translate(
                        offset: const Offset(0, 6),
                        child: OverflowBox(
                          maxWidth: _circle,
                          maxHeight: _circle,
                          child: Container(
                            width: _circle,
                            height: _circle,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.navAccent,
                              shape: BoxShape.circle,
                            ),
                            child: glyph,
                          ),
                        ),
                      )
                    : glyph,
              ),
            ),
            const SizedBox(height: _gap),
            SizedBox(
              height: _labelRow,
              child: tab.label == null
                  ? null
                  : Text(
                      tab.label!,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: theme.typography.fontFamily,
                        fontSize: 10,
                        // height 1.0 so the line box is exactly the font size and
                        // can't grow past _labelRow on a device with a larger
                        // text scale.
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
