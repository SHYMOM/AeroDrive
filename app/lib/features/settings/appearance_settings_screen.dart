import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/theme_provider.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    final colors = [
      Colors.blueAccent,
      Colors.purpleAccent,
      Colors.greenAccent,
      Colors.orangeAccent,
      Colors.redAccent,
      Colors.tealAccent,
      Colors.pinkAccent,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          // Theme Mode Segmented Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                    ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('System')),
                    ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
                  ],
                  selected: {themeState.themeMode},
                  onSelectionChanged: (newSelection) {
                    themeNotifier.setThemeMode(newSelection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          // Accent Color
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Accent Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: colors.map((color) {
                      final isSelected = themeState.accentColorValue == color.toARGB32();
                      return GestureDetector(
                        onTap: () => themeNotifier.setAccentColor(color),
                        child: Container(
                          margin: const EdgeInsets.only(right: 16),
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: isSelected ? Icon(Icons.check, color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 32),

          // File Icon Style
          _buildDropdownSetting(
            ref, 
            'File Icon Style', 
            'app_file_icon_style', 
            ['Minimal', 'Filled', 'Colored', 'Outlined'], 
            'Colored'
          ),
          
          // Language
          _buildDropdownSetting(
            ref, 
            'Language', 
            'app_language', 
            ['English', 'Spanish', 'French', 'German', 'System Default'], 
            'System Default'
          ),

          const Divider(height: 32),

          // Font Scale
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Font Size', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('A', style: TextStyle(fontSize: 14)),
                    Expanded(
                      child: Slider(
                        value: themeState.fontScale,
                        min: 0.8,
                        max: 1.4,
                        divisions: 6,
                        label: '${(themeState.fontScale * 100).round()}%',
                        onChanged: themeNotifier.setFontScale,
                      ),
                    ),
                    const Text('A', style: TextStyle(fontSize: 24)),
                  ],
                ),
              ],
            ),
          ),
          
          // High Contrast
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            title: const Text('High Contrast', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: const Text('Maximize color legibility and contrast ratios'),
            value: themeState.highContrast,
            onChanged: themeNotifier.setHighContrast,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownSetting(WidgetRef ref, String title, String key, List<String> options, String defaultVal) => FutureBuilder<String?>(
      future: ref.read(settingsRepositoryProvider).getSetting(key),
      builder: (context, snapshot) {
        final currentVal = snapshot.data ?? defaultVal;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              DropdownButton<String>(
                value: currentVal,
                items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (val) async {
                  if (val != null) {
                    await ref.read(settingsRepositoryProvider).setSetting(key, val);
                    ref.read(settingsUpdateProvider.notifier).state++;
                  }
                },
              ),
            ],
          ),
        );
      }
    );
}
