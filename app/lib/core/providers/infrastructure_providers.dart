import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';

import '../../domain/infrastructure/channel_discovery_service.dart';
import '../../domain/infrastructure/infrastructure_provisioning_service.dart';
import '../../features/telegram/telegram_manager.dart';
import '../providers/repository_providers.dart';

/// Status of the AeroDrive channel infrastructure.
enum InfrastructureStatus {
  /// No infrastructure exists yet — provisioning needed.
  notProvisioned,

  /// Infrastructure exists in settings (provisioned or restored).
  provisioned,

  /// Currently provisioning or discovering.
  loading,

  /// An error occurred.
  error,
}

final infrastructureProvisioningServiceProvider =
    Provider<InfrastructureProvisioningService>((ref) {
  return InfrastructureProvisioningService(ref);
});

final channelDiscoveryServiceProvider =
    Provider<ChannelDiscoveryService>((ref) {
  return ChannelDiscoveryService(ref);
});

/// Checks whether the AeroDrive channel infrastructure has been provisioned
/// by looking at the settings DB for stored channel IDs.
final infrastructureStatusProvider =
    FutureProvider<InfrastructureStatus>((ref) async {
  final settingsRepo = ref.read(settingsRepositoryProvider);

  final storageChannels = await settingsRepo.getSetting('storage_channels_list');
  final configChannelId = await settingsRepo.getSetting('config_channel_id');

  if ((storageChannels != null && storageChannels.isNotEmpty && storageChannels != '[]') ||
      configChannelId != null) {
    return InfrastructureStatus.provisioned;
  }

  return InfrastructureStatus.notProvisioned;
});

/// Provider that orchestrates the full "ensure infrastructure" flow:
///   1. Check if already provisioned → skip if yes
///   2. Try discovery (existing channels from descriptions)
///   3. If discovery returns enough channels → restore
///   4. Otherwise → create all channels from scratch
final ensureInfrastructureProvider =
    FutureProvider.family<void, SecretKey>((ref, masterKey) async {
  final status = await ref.read(infrastructureStatusProvider.future);
  if (status == InfrastructureStatus.provisioned) return;

  final discoveryService = ref.read(channelDiscoveryServiceProvider);
  final provisioningService = ref.read(infrastructureProvisioningServiceProvider);
  final telegramManager = ref.read(telegramManagerProvider.notifier);
  final telegramService = telegramManager.getClient('primary');
  final allAccounts = telegramManager.readyClients;
  final settingsRepo = ref.read(settingsRepositoryProvider);

  // Try discovery first
  final discoveryResult = await discoveryService.discoverInfrastructure(
    telegramService: telegramService,
    masterKey: masterKey,
  );

  if (discoveryResult.isComplete) {
    await discoveryService.restoreFromDiscovery(discoveryResult);
    return;
  }

  // Fall back to provisioning
  // Need a key salt — try to get it from settings or generate one
  final keySalt = await settingsRepo.getSetting('master_password_salt') ?? 'AeroDrive_Default_Salt';

  await provisioningService.provisionInitialInfrastructure(
    telegramService: telegramService,
    masterKey: masterKey,
    masterKeySalt: keySalt,
    allAccounts: allAccounts,
  );
});
