import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerodrive/features/drive/widgets/channel_setup_wizard_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ChannelSetupWizardDialog displays 4 required channels and mandatory rules', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChannelSetupWizardDialog(),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify title and subtitle
    expect(find.text('Welcome to AeroDrive'), findsOneWidget);
    expect(find.text('Initial Infrastructure Setup'), findsOneWidget);

    // Verify the 4 required channels are explicitly listed
    expect(find.text('AeroDrive Storage 1'), findsOneWidget);
    expect(find.text('AeroDrive Storage 2'), findsOneWidget);
    expect(find.text('AeroDrive Config'), findsOneWidget);
    expect(find.text('AeroDrive Shared'), findsOneWidget);

    // Verify critical safety and privacy rules
    expect(find.text('CRITICAL PRIVACY & SECURITY RULES'), findsOneWidget);
    expect(find.textContaining('Do NOT add any person or bot to these channels.'), findsOneWidget);
    expect(find.textContaining('Do NOT edit, delete, or remove the descriptions of these channels.'), findsOneWidget);
    expect(find.textContaining('Channels will be renamed and given the AeroDrive app icon automatically.'), findsOneWidget);

    // Verify action buttons
    expect(find.text('Auto-Create All 4 Channels (Recommended)'), findsOneWidget);
    expect(find.text('Link Existing Telegram Channels'), findsOneWidget);
    expect(find.text('Remind Me Later'), findsOneWidget);
  });
}
