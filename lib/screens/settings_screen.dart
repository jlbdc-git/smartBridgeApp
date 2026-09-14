import 'package:flutter/material.dart';

import '../models/ui_preferences.dart';
import '../models/user_profile.dart';
import '../services/permission_handler.dart';
import '../services/session_service.dart';
import 'legacy/settings_screen.dart';
import 'legacy/sign_translator_screen.dart';

/// Settings for the messaging app.
///
/// Includes every item required by the spec: name, role, text-to-speech,
/// speech recognition, notifications, font size, high contrast, delete
/// conversations, remove friends and privacy shortcuts. The original
/// SmartBridge sign-translator settings stay available under "Sign tools".
class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    super.key,
    required this.session,
    required this.onPreferencesChanged,
  });

  final SessionService session;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.session.profile?.name ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  SessionService get _session => widget.session;

  @override
  Widget build(BuildContext context) {
    final AppUiPreferences prefs = _session.ui;
    final UserProfile? profile = _session.profile;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------------- Profile ----------------
          _Section(
            title: 'Profile',
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
                onSubmitted: (String value) =>
                    _session.updateProfile(name: value),
              ),
              const SizedBox(height: 12),
              Text(
                'Role',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment<UserRole>(
                    value: UserRole.blind,
                    icon: Icon(Icons.visibility_off),
                    label: Text('Blind'),
                  ),
                  ButtonSegment<UserRole>(
                    value: UserRole.deaf,
                    icon: Icon(Icons.hearing),
                    label: Text('Deaf'),
                  ),
                ],
                selected: <UserRole>{profile?.role ?? UserRole.blind},
                onSelectionChanged: (Set<UserRole> selection) {
                  _session.updateProfile(role: selection.first);
                  setState(() {});
                },
              ),
            ],
          ),
          // ---------------- Voice ----------------
          _Section(
            title: 'Voice',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Text-to-speech confirmations'),
                subtitle: const Text(
                  'Reads messages and confirmations aloud (blind mode).',
                ),
                value: _session.notificationsEnabled,
                onChanged: (bool value) {
                  _session.setNotificationsEnabled(value);
                  setState(() {});
                },
              ),
              _LabeledSlider(
                label: 'Speech rate',
                value: prefs.ttsRate,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                valueLabel: prefs.ttsRate.toStringAsFixed(1),
                onChanged: (double value) => widget.onPreferencesChanged(
                  prefs.copyWith(ttsRate: value),
                ),
              ),
              _LabeledSlider(
                label: 'Voice pitch',
                value: prefs.ttsPitch,
                min: 0.5,
                max: 2.0,
                divisions: 15,
                valueLabel: prefs.ttsPitch.toStringAsFixed(1),
                onChanged: (double value) => widget.onPreferencesChanged(
                  prefs.copyWith(ttsPitch: value),
                ),
              ),
              _LabeledSlider(
                label: 'Voice volume',
                value: prefs.ttsVolume,
                min: 0.0,
                max: 1.0,
                divisions: 10,
                valueLabel: prefs.ttsVolume.toStringAsFixed(1),
                onChanged: (double value) => widget.onPreferencesChanged(
                  prefs.copyWith(ttsVolume: value),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.mic_rounded),
                title: const Text('Speech recognition'),
                subtitle: const Text(
                  'Microphone permission is requested when you first '
                  'record a voice message.',
                ),
                trailing: TextButton(
                  onPressed: PermissionHandler.openAppSettingsPage,
                  child: const Text('Open settings'),
                ),
              ),
            ],
          ),
          // ---------------- Alerts ----------------
          _Section(
            title: 'Alerts',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visual notifications'),
                subtitle: const Text(
                  'Show new-message banners (deaf mode).',
                ),
                value: _session.notificationsEnabled,
                onChanged: (bool value) {
                  _session.setNotificationsEnabled(value);
                  setState(() {});
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vibration'),
                subtitle: const Text(
                  'Vibrate on incoming messages (deaf mode).',
                ),
                value: _session.vibrationEnabled,
                onChanged: (bool value) {
                  _session.setVibrationEnabled(value);
                  setState(() {});
                },
              ),
            ],
          ),
          // ---------------- Accessibility ----------------
          _Section(
            title: 'Accessibility',
            children: [
              _LabeledSlider(
                label: 'Font size',
                value: prefs.textScale,
                min: 0.85,
                max: 1.4,
                divisions: 11,
                valueLabel: '${prefs.textScale.toStringAsFixed(2)}x',
                onChanged: (double value) => widget.onPreferencesChanged(
                  prefs.copyWith(textScale: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('High contrast'),
                value: prefs.highContrast,
                onChanged: (bool value) => widget.onPreferencesChanged(
                  prefs.copyWith(highContrast: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                value: prefs.reduceMotion,
                onChanged: (bool value) => widget.onPreferencesChanged(
                  prefs.copyWith(reduceMotion: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Haptics'),
                value: prefs.hapticsEnabled,
                onChanged: (bool value) => widget.onPreferencesChanged(
                  prefs.copyWith(hapticsEnabled: value),
                ),
              ),
            ],
          ),
          // ---------------- Sign tools (original feature set) ----------------
          _Section(
            title: 'Sign tools',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sign_language_rounded),
                title: const Text('Open sign translator'),
                subtitle: const Text(
                  'The original SmartBridge camera sign recognition.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => SignTranslatorScreen(
                      prefs: _session.ui,
                      onAddHistory: (_) {},
                      onPreferencesChanged: widget.onPreferencesChanged,
                    ),
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Recognition settings'),
                subtitle: const Text(
                  'Thresholds, frame stride and voice output for sign tools.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => LegacySettingsScreen(
                      prefs: _session.ui,
                      onPreferencesChanged: widget.onPreferencesChanged,
                      onClearHistory: () {},
                    ),
                  ),
                ),
              ),
            ],
          ),
          // ---------------- Privacy ----------------
          _Section(
            title: 'Privacy',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_sweep_rounded),
                title: const Text('Delete all conversations'),
                subtitle: const Text(
                  'Removes every stored message from this device.',
                ),
                onTap: () async {
                  final bool? confirmed = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: const Text('Delete all conversations?'),
                      content: const Text(
                        'Every message stored on this device will be removed. '
                        'This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _session.deleteAllConversations();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('All conversations deleted')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_remove_rounded),
                title: const Text('Remove friends'),
                subtitle: const Text(
                  'Manage your friend list and remove connections.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).pushNamed('/friends'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline_rounded),
                title: Text('Private by design'),
                subtitle: Text(
                  'No public directory, no search, no analytics. Messages '
                  'stay on your device and travel only over your local '
                  'Wi-Fi. Codes expire after 30 minutes.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
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
