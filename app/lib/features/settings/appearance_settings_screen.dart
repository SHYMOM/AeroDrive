import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_providers.dart';
import '../../core/theme/aerodrive_theme.dart';
import '../../core/theme/theme_provider.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState   = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final scheme       = Theme.of(context).colorScheme;
    final textTheme    = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [

          // ─── Theme Mode ───────────────────────────────────────────
          _SectionHeader(label: 'Theme Mode'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: ThemeMode.values.map((mode) {
                final isSelected = themeState.themeMode == mode;
                final (icon, label) = switch (mode) {
                  ThemeMode.light  => (Icons.light_mode_outlined,  'Light'),
                  ThemeMode.dark   => (Icons.dark_mode_outlined,   'Dark'),
                  ThemeMode.system => (Icons.brightness_auto,       'System'),
                };
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _ModeCard(
                      icon: icon,
                      label: label,
                      isSelected: isSelected,
                      primaryColor: scheme.primary,
                      onTap: () => themeNotifier.setThemeMode(mode),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 8),
          const Divider(indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // ─── Color Theme Presets ───────────────────────────────────
          _SectionHeader(label: 'Color Theme'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.5,
              ),
              itemCount: AeroDriveTheme.presets.length,
              itemBuilder: (context, i) {
                final preset = AeroDriveTheme.presets[i];
                final isSelected =
                    themeState.accentColorValue == preset.primary.toARGB32();
                return _PresetCard(
                  preset: preset,
                  isSelected: isSelected,
                  onTap: () => themeNotifier.setAccentColor(preset.primary),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          const Divider(indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // ─── Font Size ────────────────────────────────────────────
          _SectionHeader(label: 'Font Size'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('A', style: textTheme.bodySmall),
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
                    Text('A', style: textTheme.titleMedium),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(themeState.fontScale * 100).round()}%',
                    style: textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          const Divider(indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // ─── High Contrast ────────────────────────────────────────
          _SectionHeader(label: 'Accessibility'),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            secondary: Icon(Icons.contrast, color: scheme.primary),
            title: Text('High Contrast', style: textTheme.titleSmall),
            subtitle: Text(
              'Maximise legibility with stronger colour contrast ratios',
              style: textTheme.bodySmall,
            ),
            value: themeState.highContrast,
            onChanged: themeNotifier.setHighContrast,
          ),

          const SizedBox(height: 8),
          const Divider(indent: 20, endIndent: 20),
          const SizedBox(height: 8),

          // ─── File Icon Style ──────────────────────────────────────
          _SectionHeader(label: 'Files'),
          _DropdownTile(
            settingKey: 'app_file_icon_style',
            label: 'File Icon Style',
            options: const ['Minimal', 'Filled', 'Colored', 'Outlined'],
            defaultVal: 'Colored',
          ),

          // ─── Language ─────────────────────────────────────────────
          _SectionHeader(label: 'Language'),
          _DropdownTile(
            settingKey: 'app_language',
            label: 'Display Language',
            options: const ['English', 'Spanish', 'French', 'German', 'System Default'],
            defaultVal: 'System Default',
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.primaryColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? primaryColor : cs.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? primaryColor : cs.onSurfaceVariant, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? primaryColor : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final AeroThemePreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? preset.primary : cs.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: preset.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              // Gradient swatch + icon
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: preset.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(preset.icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preset.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? preset.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: preset.primary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropdownTile extends ConsumerWidget {
  const _DropdownTile({
    required this.settingKey,
    required this.label,
    required this.options,
    required this.defaultVal,
  });

  final String settingKey;
  final String label;
  final List<String> options;
  final String defaultVal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String?>(
      future: ref.read(settingsRepositoryProvider).getSetting(settingKey),
      builder: (context, snapshot) {
        final currentVal = snapshot.data ?? defaultVal;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          trailing: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentVal,
              borderRadius: BorderRadius.circular(12),
              items: options
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (val) async {
                if (val != null) {
                  await ref.read(settingsRepositoryProvider).setSetting(settingKey, val);
                  ref.read(settingsUpdateProvider.notifier).state++;
                }
              },
            ),
          ),
        );
      },
    );
  }
}
