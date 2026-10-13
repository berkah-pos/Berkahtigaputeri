import 'package:flutter_test/flutter_test.dart';

/// Pumps finite frames until a widget becomes visible, without waiting for
/// unrelated indeterminate indicators in inactive IndexedStack children.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 60,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder after $maxPumps test pumps.');
}
