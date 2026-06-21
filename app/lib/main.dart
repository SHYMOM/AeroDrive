import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/aerodrive_theme.dart';
import 'core/routing/app_router.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AeroDrive application entry point.
///
/// Wraps the app in a [ProviderScope] for Riverpod state management
/// and configures [MaterialApp.router] with the AeroDrive dark theme
/// and [GoRouter]-based navigation.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load Telegram API credentials from .env
  await dotenv.load(fileName: ".env");
  
  runApp(const ProviderScope(child: AeroDriveApp()));
}

/// Root application widget.
class AeroDriveApp extends ConsumerWidget {
  const AeroDriveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'AeroDrive',
      debugShowCheckedModeBanner: false,
      theme: AeroDriveTheme.dark,
      routerConfig: router,
    );
  }
}
