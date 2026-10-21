import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers.dart';
import 'package:aerodrive/core/routing/app_router.dart';
import 'package:aerodrive/features/auth/auth_provider.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';

class FakeTelegramService extends StateNotifier<TelegramAuthState> implements TelegramService {
  FakeTelegramService([super.initialState = TelegramAuthState.initial]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Router and Splash Navigation Tests', () {
    test('AppRouterNotifier notifies listeners when authProvider updates', () {
      final fakeTelegram = FakeTelegramService(TelegramAuthState.initial);
      final container = ProviderContainer(
        overrides: [
          telegramServiceProvider.overrideWith((ref) => fakeTelegram),
        ],
      );

      final notifier = container.read(routerNotifierProvider);
      var notificationCount = 0;
      notifier.addListener(() {
        notificationCount++;
      });

      // Initially 0 notifications
      expect(notificationCount, equals(0));

      // Force state change
      container.read(authProvider.notifier).forceUnauthenticated();
      expect(container.read(authProvider), equals(AuthState.unauthenticated));
      expect(notificationCount, greaterThanOrEqualTo(1));

      // Toggle hasNavigatedPastSplashProvider
      final previousCount = notificationCount;
      container.read(hasNavigatedPastSplashProvider.notifier).state = true;
      expect(notificationCount, greaterThan(previousCount));

      container.dispose();
    });

    test('routerProvider provides a valid GoRouter with /splash initialLocation', () {
      final fakeTelegram = FakeTelegramService(TelegramAuthState.initial);
      final container = ProviderContainer(
        overrides: [
          telegramServiceProvider.overrideWith((ref) => fakeTelegram),
        ],
      );

      final router = container.read(routerProvider);
      expect(router, isNotNull);
      expect(router.routeInformationProvider.value.uri.path, equals('/splash'));

      container.dispose();
    });
  });
}
