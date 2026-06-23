import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aerodrive/core/providers/repository_providers.dart';

class LoadBalancingScreen extends ConsumerStatefulWidget {
  const LoadBalancingScreen({super.key});

  @override
  ConsumerState<LoadBalancingScreen> createState() => _LoadBalancingScreenState();
}

class _LoadBalancingScreenState extends ConsumerState<LoadBalancingScreen> {
  String _selectedStrategy = 'round_robin';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsRepositoryProvider);
    final val = await settings.getSetting('load_balancing_strategy') ?? 'round_robin';
    if (mounted) {
      setState(() {
        _selectedStrategy = val;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Load Balancing Strategy')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Load Balancing Strategy'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 24, right: 24, bottom: 16),
            child: Text(
              'Distribute your uploads across multiple storage channels to bypass single-channel upload limits and organize data efficiently.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          RadioListTile<String>(
            title: const Text('Round Robin'),
            subtitle: const Text('Evenly distribute files across all available channels one by one.'),
            value: 'round_robin',
            groupValue: _selectedStrategy,
            onChanged: (val) => setState(() => _selectedStrategy = val!),
          ),
          RadioListTile<String>(
            title: const Text('Fill First'),
            subtitle: const Text('Fill one channel completely before moving to the next.'),
            value: 'fill_first',
            groupValue: _selectedStrategy,
            onChanged: (val) => setState(() => _selectedStrategy = val!),
          ),
          RadioListTile<String>(
            title: const Text('Random'),
            subtitle: const Text('Randomly select a channel for each file.'),
            value: 'random',
            groupValue: _selectedStrategy,
            onChanged: (val) => setState(() => _selectedStrategy = val!),
          ),
          RadioListTile<String>(
            title: const Text('Size-Based (Tiering)'),
            subtitle: const Text('Send small files to Channel A, large files to Channel B.'),
            value: 'size_based',
            groupValue: _selectedStrategy,
            onChanged: (val) => setState(() => _selectedStrategy = val!),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FilledButton(
              onPressed: () async {
                final settings = ref.read(settingsRepositoryProvider);
                await settings.setSetting('load_balancing_strategy', _selectedStrategy);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Strategy saved!')));
                Navigator.pop(context);
              },
              child: const Text('Save Configuration'),
            ),
          )
        ],
      ),
    );
  }
}
