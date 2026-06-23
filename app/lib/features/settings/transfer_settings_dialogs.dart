import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class ParallelThreadsDialog extends ConsumerStatefulWidget {
  const ParallelThreadsDialog({super.key});

  @override
  ConsumerState<ParallelThreadsDialog> createState() => _ParallelThreadsDialogState();
}

class _ParallelThreadsDialogState extends ConsumerState<ParallelThreadsDialog> {
  String _threads = '3';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('parallel_threads') ?? '3';
    if (mounted) setState(() => _threads = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Parallel Threads'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(title: const Text('1 Thread (Slow & Steady)'), value: '1', groupValue: _threads, onChanged: (v) => setState(() => _threads = v!)),
          RadioListTile<String>(title: const Text('3 Threads (Default)'), value: '3', groupValue: _threads, onChanged: (v) => setState(() => _threads = v!)),
          RadioListTile<String>(title: const Text('5 Threads (Fast)'), value: '5', groupValue: _threads, onChanged: (v) => setState(() => _threads = v!)),
          RadioListTile<String>(title: const Text('10 Threads (Aggressive)'), value: '10', groupValue: _threads, onChanged: (v) => setState(() => _threads = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('parallel_threads', _threads);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class BandwidthLimitDialog extends ConsumerStatefulWidget {
  const BandwidthLimitDialog({super.key});

  @override
  ConsumerState<BandwidthLimitDialog> createState() => _BandwidthLimitDialogState();
}

class _BandwidthLimitDialogState extends ConsumerState<BandwidthLimitDialog> {
  String _limit = 'Uncapped';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('bandwidth_limit') ?? 'Uncapped';
    if (mounted) setState(() => _limit = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bandwidth Limit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(title: const Text('Uncapped'), value: 'Uncapped', groupValue: _limit, onChanged: (v) => setState(() => _limit = v!)),
          RadioListTile<String>(title: const Text('1 MB/s'), value: '1', groupValue: _limit, onChanged: (v) => setState(() => _limit = v!)),
          RadioListTile<String>(title: const Text('5 MB/s'), value: '5', groupValue: _limit, onChanged: (v) => setState(() => _limit = v!)),
          RadioListTile<String>(title: const Text('10 MB/s'), value: '10', groupValue: _limit, onChanged: (v) => setState(() => _limit = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('bandwidth_limit', _limit);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class AutoRetryCountDialog extends ConsumerStatefulWidget {
  const AutoRetryCountDialog({super.key});

  @override
  ConsumerState<AutoRetryCountDialog> createState() => _AutoRetryCountDialogState();
}

class _AutoRetryCountDialogState extends ConsumerState<AutoRetryCountDialog> {
  String _retry = '3';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('auto_retry_count') ?? '3';
    if (mounted) setState(() => _retry = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Auto-Retry Count'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(title: const Text('1 Attempt'), value: '1', groupValue: _retry, onChanged: (v) => setState(() => _retry = v!)),
          RadioListTile<String>(title: const Text('3 Attempts (Default)'), value: '3', groupValue: _retry, onChanged: (v) => setState(() => _retry = v!)),
          RadioListTile<String>(title: const Text('5 Attempts'), value: '5', groupValue: _retry, onChanged: (v) => setState(() => _retry = v!)),
          RadioListTile<String>(title: const Text('Infinite'), value: 'Infinite', groupValue: _retry, onChanged: (v) => setState(() => _retry = v!)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('auto_retry_count', _retry);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class UploadQualityDialog extends ConsumerStatefulWidget {
  const UploadQualityDialog({super.key});

  @override
  ConsumerState<UploadQualityDialog> createState() => _UploadQualityDialogState();
}

class _UploadQualityDialogState extends ConsumerState<UploadQualityDialog> {
  String _quality = 'Original';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final val = await ref.read(settingsRepositoryProvider).getSetting('upload_quality') ?? 'Original';
    if (mounted) setState(() => _quality = val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Default Upload Quality'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RadioListTile<String>(
            title: const Text('Original'),
            subtitle: const Text('No compression (Best quality)'),
            value: 'Original',
            groupValue: _quality,
            onChanged: (v) => setState(() => _quality = v!),
          ),
          RadioListTile<String>(
            title: const Text('High'),
            subtitle: const Text('Light compression (~80% quality)'),
            value: 'High',
            groupValue: _quality,
            onChanged: (v) => setState(() => _quality = v!),
          ),
          RadioListTile<String>(
            title: const Text('Medium'),
            subtitle: const Text('Heavy compression (Saves space)'),
            value: 'Medium',
            groupValue: _quality,
            onChanged: (v) => setState(() => _quality = v!),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await ref.read(settingsRepositoryProvider).setSetting('upload_quality', _quality);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
