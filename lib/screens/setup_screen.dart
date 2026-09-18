import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Welcome + Setup screen.
///
/// Step 1: "I AM BLIND" or "I AM DEAF" - the whole UI adapts to this choice.
/// Step 2: name entry (only personal data stored, stays on the device).
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.session,
    required this.onSetupComplete,
  });

  final SessionService session;
  final VoidCallback onSetupComplete;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  UserRole? _role;
  final TextEditingController _nameController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Voice guidance is announced for blind users right after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _greet());
  }

  Future<void> _greet() async {
    // Announcement is skipped in deaf mode: no critical info by sound only.
    final UserRole? role = _role ?? widget.session.profile?.role;
    if (role == UserRole.deaf) return;
    await widget.session.tts.speak(
      'Welcome to SmartBridge Messages. '
      'Step 1. Choose I am blind, or I am deaf. '
      'Step 2. Type your name. Then press start.',
    );
  }

  Future<void> _complete() async {
    if (_role == null || _saving) return;
    setState(() => _saving = true);
    await widget.session.completeSetup(
      name: _nameController.text,
      role: _role!,
    );
    if (_role == UserRole.blind) {
      await widget.session.tts
          .speakConfirmation('Setup complete. You can start messaging.');
    }
    if (!mounted) return;
    widget.onSetupComplete();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool blindChosen = _role == UserRole.blind;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(
                  Icons.hearing_disabled,
                  size: 64,
                  color: scheme.primary,
                  semanticLabel: 'SmartBridge Messages',
                ),
                const SizedBox(height: 12),
                Text(
                  'SmartBridge Messages',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Different ways of communicating, one shared conversation.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                Text(
                  'I am...',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.visibility_off,
                  title: 'I AM BLIND',
                  subtitle: 'Voice messages, spoken replies, large buttons',
                  selected: _role == UserRole.blind,
                  onTap: () => setState(() => _role = UserRole.blind),
                ),
                const SizedBox(height: 12),
                _RoleCard(
                  icon: Icons.hearing,
                  title: 'I AM DEAF',
                  subtitle: 'Typing, readable text, emotion stickers, vibration',
                  selected: _role == UserRole.deaf,
                  onTap: () => setState(() => _role = UserRole.deaf),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 24,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    hintText: 'How friends will see you',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 20),
                BigButton(
                  label: 'Start',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _role == null ? null : _complete,
                  subtext: 'You can change this later in Settings',
                ),
                if (blindChosen)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Tip: every button here is large and spoken aloud.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // The first screen a blind user meets: the card announces itself as a
    // button and says whether it is the current choice, instead of leaving the
    // checkmark to be discovered visually.
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $subtitle',
      onTap: onTap,
      child: Material(
        color:
            selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Row(
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: scheme.primary, size: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
