import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/main.dart';

void main() {
  testWidgets('AeroDrive smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: AeroDriveApp()));

    // Verify that the drive screen displays.
    expect(find.text('My Drive'), findsOneWidget);
    expect(find.text('Your drive is empty'), findsOneWidget);
  });
}
