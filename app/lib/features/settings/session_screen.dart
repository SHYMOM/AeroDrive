import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:aerodrive/core/theme/app_colors.dart';
import 'package:aerodrive/features/telegram/telegram_service.dart';
import 'package:aerodrive/features/telegram/telegram_manager.dart';

class SessionScreen extends ConsumerWidget {
  const SessionScreen({super.key});

  String _formatLastActive(int timestampSeconds) {
    if (timestampSeconds == 0) return 'Unknown';
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestampSeconds * 1000);
    final difference = now.difference(date);

    if (difference.inSeconds < 60) {
      return 'Active now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  IconData _getDeviceIcon(String deviceModel, String systemVersion) {
    final model = deviceModel.toLowerCase();
    final sys = systemVersion.toLowerCase();
    if (model.contains('windows') || sys.contains('windows')) {
      return Icons.laptop_windows;
    } else if (model.contains('mac') || sys.contains('mac') || model.contains('os x') || sys.contains('os x')) {
      return Icons.laptop_mac;
    } else if (model.contains('linux') || sys.contains('linux') || model.contains('ubuntu')) {
      return Icons.laptop_chromebook;
    } else if (model.contains('android') || sys.contains('android')) {
      return Icons.phone_android;
    } else if (model.contains('iphone') || model.contains('ipad') || sys.contains('ios')) {
      return Icons.phone_iphone;
    }
    return Icons.devices;
  }

  Future<void> _confirmTerminateSession(BuildContext context, WidgetRef ref, Map<String, dynamic> session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Terminate Session', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to terminate the session on ${session['device_model'] ?? 'this device'} for account "${session['accountName']}"?\n\n'
          'This will log out the device immediately.',
          style: const TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final accountId = session['accountId'] as String;
        final manager = ref.read(telegramManagerProvider.notifier);
        final client = manager.getClient(accountId);
        
        await client.terminateSession(session['id']);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session terminated successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        ref.invalidate(activeSessionsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to terminate session: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _confirmTerminateAllOtherSessions(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Terminate All Other Sessions', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to terminate all other active sessions across ALL logged-in accounts?\n\n'
          'This will log out all other devices immediately.',
          style: TextStyle(color: AppColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terminate All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final manager = ref.read(telegramManagerProvider.notifier);
        for (final client in manager.readyClients) {
          if (client.authState == TelegramAuthState.ready) {
            await client.terminateAllOtherSessions();
          }
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('All other sessions terminated successfully'),
              backgroundColor: AppColors.success,
            ),
          );
        }
        ref.invalidate(activeSessionsProvider);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to terminate other sessions: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(activeSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Sessions',
            onPressed: () => ref.invalidate(activeSessionsProvider),
          ),
        ],
      ),
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.devices, size: 64, color: AppColors.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'No active sessions found',
                    style: TextStyle(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          final currentSessions = sessions.where((s) => s['is_current'] == true).toList();
          final otherSessions = sessions.where((s) => s['is_current'] != true).toList();

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(activeSessionsProvider);
              await ref.read(activeSessionsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              children: [
                if (currentSessions.isNotEmpty) ...[
                  const Text(
                    'Current Sessions',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  ...currentSessions.map((currentSession) {
                    return Card(
                      color: AppColors.surfaceElevated,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getDeviceIcon(
                                  currentSession['device_model'] ?? '',
                                  currentSession['system_version'] ?? '',
                                ),
                                size: 32,
                                color: AppColors.primaryLight,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          currentSession['device_model'] ?? 'Unknown Device',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.success.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Current',
                                          style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${currentSession['application_name'] ?? 'AeroDrive'} • ${currentSession['application_version'] ?? ''}',
                                    style: TextStyle(fontSize: 13, color: AppColors.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${currentSession['ip_address'] ?? 'Unknown IP'} • ${currentSession['location'] ?? 'Unknown location'}',
                                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.8)),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Account: ${currentSession['accountName']}',
                                      style: const TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 24),
                ],
                if (otherSessions.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Other Active Sessions',
                        style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryLight, fontSize: 14),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        onPressed: () => _confirmTerminateAllOtherSessions(context, ref),
                        child: const Text('Terminate All Others'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...otherSessions.map((session) {
                    return Card(
                      color: AppColors.surface,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.outline, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppColors.surfaceElevated,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _getDeviceIcon(
                                  session['device_model'] ?? '',
                                  session['system_version'] ?? '',
                                ),
                                size: 24,
                                color: AppColors.onSurface,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          session['device_model'] ?? 'Unknown Device',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          session['accountName'] ?? 'Unknown',
                                          style: const TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${session['application_name'] ?? 'AeroDrive'} • ${session['application_version'] ?? ''}',
                                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${session['ip_address'] ?? 'Unknown IP'} • ${session['location'] ?? 'Unknown location'}',
                                    style: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant.withOpacity(0.8)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last active: ${_formatLastActive(session['last_active_date'] ?? 0)}',
                                    style: TextStyle(fontSize: 11, color: AppColors.onSurfaceVariant.withOpacity(0.6)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: AppColors.error),
                              tooltip: 'Terminate Session',
                              onPressed: () => _confirmTerminateSession(context, ref, session),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ] else if (currentSessions.isNotEmpty) ...[
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'No other active sessions',
                        style: TextStyle(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              const Text(
                'Failed to load active sessions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () => ref.invalidate(activeSessionsProvider),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
