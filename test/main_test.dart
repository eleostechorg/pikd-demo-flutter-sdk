import 'package:flutter_test/flutter_test.dart';
import 'package:pikd_flutter_demo/main.dart';

void main() {
  testWidgets('shows configuration guidance before local values are supplied', (
    tester,
  ) async {
    await tester.pumpWidget(const PikdExperienceDemoApp());

    expect(find.text('Configuration required'), findsOneWidget);
    expect(find.text('• PIKD_BASE'), findsOneWidget);
  });
}
