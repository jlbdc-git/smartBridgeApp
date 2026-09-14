import 'package:flutter/material.dart';

import '../../models/ui_preferences.dart';
import '../../services/permission_handler.dart';

/// Original settings page (extracted unchanged).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.prefs,
    required this.onPreferencesChanged,
    required this.onClearHistory,
  });

  final AppUiPreferences prefs;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;
  final VoidCallback onClearHistory;

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Accessibility',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final bool compact = constraints.maxWidth < 420;
                    if (compact) {
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ThemeMode.values.map((ThemeMode mode) {
                          return ChoiceChip(
                            avatar: Icon(
                              _themeModeIcon(mode),
                              size: 18,
                              color: prefs.themeMode == mode
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                            label: Text(_themeModeLabel(mode)),
                            selected: prefs.themeMode == mode,
                            onSelected: (_) {
                              onPreferencesChanged(
                                prefs.copyWith(themeMode: mode),
                              );
                            },
                          );
                        }).toList(),
                      );
                    }

                    return SegmentedButton<ThemeMode>(
                      showSelectedIcon: false,
                      multiSelectionEnabled: false,
                      segments: const [
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('System'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light'),
                        ),
                        ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: <ThemeMode>{prefs.themeMode},
                      onSelectionChanged: (Set<ThemeMode> selection) {
                        onPreferencesChanged(
                          prefs.copyWith(themeMode: selection.first),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 10),
                _LabeledSlider(
                  label: 'Text size',
                  value: prefs.textScale,
                  min: 0.85,
                  max: 1.4,
                  divisions: 11,
                  valueLabel: '${prefs.textScale.toStringAsFixed(2)}x',
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(textScale: value));
                  },
                ),
                Row(
                  children: [
                    Expanded(child: const Text('High contrast')),
                    Switch.adaptive(
                      value: prefs.highContrast,
                      onChanged: (bool value) => onPreferencesChanged(prefs.copyWith(highContrast: value)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: const Text('Reduce motion')),
                    Switch.adaptive(
                      value: prefs.reduceMotion,
                      onChanged: (bool value) => onPreferencesChanged(prefs.copyWith(reduceMotion: value)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: const Text('Haptics')),
                    Switch.adaptive(
                      value: prefs.hapticsEnabled,
                      onChanged: (bool value) => onPreferencesChanged(prefs.copyWith(hapticsEnabled: value)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recognition and Voice',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: const Text('Auto-speak')),
                    Switch.adaptive(
                      value: prefs.autoSpeakSigns,
                      onChanged: (bool value) => onPreferencesChanged(prefs.copyWith(autoSpeakSigns: value)),
                    ),
                  ],
                ),
                _LabeledSlider(
                  label: 'Recognition threshold',
                  value: prefs.recognitionThreshold,
                  min: 10,
                  max: 95,
                  divisions: 17,
                  valueLabel: '${prefs.recognitionThreshold.toStringAsFixed(0)}%',
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(recognitionThreshold: value));
                  },
                ),
                _LabeledSlider(
                  label: 'History confidence',
                  value: prefs.historyConfidenceThreshold,
                  min: 35,
                  max: 99,
                  divisions: 16,
                  valueLabel: '${prefs.historyConfidenceThreshold.toStringAsFixed(0)}%',
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(historyConfidenceThreshold: value));
                  },
                ),
                _LabeledSlider(
                  label: 'Frame stride',
                  value: prefs.frameStride.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  valueLabel: prefs.frameStride.toString(),
                  onChanged: (double value) {
                    onPreferencesChanged(
                      prefs.copyWith(frameStride: value.round()),
                    );
                  },
                ),
                _LabeledSlider(
                  label: 'Voice speed',
                  value: prefs.ttsRate,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  valueLabel: prefs.ttsRate.toStringAsFixed(1),
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(ttsRate: value));
                  },
                ),
                _LabeledSlider(
                  label: 'Voice pitch',
                  value: prefs.ttsPitch,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  valueLabel: prefs.ttsPitch.toStringAsFixed(1),
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(ttsPitch: value));
                  },
                ),
                _LabeledSlider(
                  label: 'Voice volume',
                  value: prefs.ttsVolume,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  valueLabel: prefs.ttsVolume.toStringAsFixed(1),
                  onChanged: (double value) {
                    onPreferencesChanged(prefs.copyWith(ttsVolume: value));
                  },
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_applications_outlined),
                  title: const Text('Open app permissions'),
                  subtitle: const Text(
                    'Manage camera and microphone access from system settings.',
                  ),
                  onTap: PermissionHandler.openAppSettingsPage,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear translation history'),
                  onTap: onClearHistory,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}


/// Adapter exposing the preserved settings page under the name used by the
/// messaging settings screen.
class LegacySettingsScreen extends StatelessWidget {
  const LegacySettingsScreen({
    super.key,
    required this.prefs,
    required this.onPreferencesChanged,
    required this.onClearHistory,
  });

  final AppUiPreferences prefs;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign tool settings')),
      body: SettingsPage(
        prefs: prefs,
        onPreferencesChanged: onPreferencesChanged,
        onClearHistory: onClearHistory,
      ),
    );
  }
}
