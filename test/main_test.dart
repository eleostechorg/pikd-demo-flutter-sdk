import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show Key;
import 'package:pikd_flutter_demo/main.dart';
import 'package:pikd_flutter_magnum_experience/pikd_flutter_magnum_experience.dart'
    show PikdLocale;

void main() {
  testWidgets('shows configuration guidance before local values are supplied', (
    tester,
  ) async {
    await tester.pumpWidget(const PikdExperienceDemoApp());

    expect(find.byKey(const Key('demo-language-selector')), findsOneWidget);
    expect(find.text('• PIKD_BASE'), findsOneWidget);
  });

  testWidgets('uses the selected launch locale for host copy', (tester) async {
    await tester.pumpWidget(
      const PikdExperienceDemoApp(initialLocale: PikdLocale.russian),
    );

    await tester.tap(find.byKey(const Key('demo-language-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Қазақша').last);
    await tester.pump();

    expect(find.text('Конфигурация қажет'), findsOneWidget);
  });
}
