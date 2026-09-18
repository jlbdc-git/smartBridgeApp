import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../services/session_service.dart';
import '../services/translation_service.dart';
import '../widgets/accessibility.dart';
import '../widgets/emotion_badge.dart';

/// DEAF pipeline: Typed message -> natural English -> Select emotion ->
/// Preview -> Send.
///
/// The improver fixes grammar and structure and makes the English natural
/// while preserving the original intent; nothing is added. The emotion is
/// ALWAYS chosen manually - the app never infers feelings.
class DeafTranslatorScreen extends StatefulWidget {
  const DeafTranslatorScreen({
    super.key,
    required this.session,
    required this.friendName,
  });

  final SessionService session;
  final String friendName;

  @override
  State<DeafTranslatorScreen> createState() => _DeafTranslatorScreenState();
}

class _DeafTranslatorScreenState extends State<DeafTranslatorScreen> {
  final TextEditingController _input = TextEditingController();
  final DeafTranslator _translator = const DeafTranslator();

  String _improved = '';
  Emotion? _emotion;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
  }

  void _onInputChanged() {
    setState(() {
      _improved = _improveSafely(_input.text);
    });
  }

  /// Translation failure fallback: original text wins over a lost message.
  String _improveSafely(String input) {
    try {
      return _translator.improve(input);
    } catch (_) {
      return input;
    }
  }

  bool get _canSend =>
      _improved.trim().isNotEmpty && _emotion != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Message to ${widget.friendName}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------------- Step 1: type ----------------
            Text(
              '1. Type your message',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _input,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'i go mall tomorrow you want come?',
              ),
            ),
            const SizedBox(height: 20),
            // ---------------- Step 2: emotion ----------------
            Text(
              '2. Pick your emotion (required)',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final Emotion emotion in Emotion.values)
                  _EmotionChoice(
                    emotion: emotion,
                    selected: _emotion == emotion,
                    onTap: () => setState(() => _emotion = emotion),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // ---------------- Step 3: preview ----------------
            Text(
              '3. Preview before sending',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            PreviewCard(
              title: 'WHAT WILL BE SENT',
              body: _improved.trim().isEmpty
                  ? 'Your improved message appears here'
                  : _improved,
              trailing: _emotion == null
                  ? Text(
                      'no emotion yet',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : EmotionBadge(emotion: _emotion!),
            ),
            const SizedBox(height: 8),
            if (_input.text.trim().isNotEmpty &&
                _improved.trim() != _input.text.trim())
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Your original words are kept in the message so your friend '
                  'can see both versions.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12.5,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            BigButton(
              label: 'Send message',
              icon: Icons.send_rounded,
              onPressed: _canSend
                  ? () => Navigator.of(context).pop(
                        ChatMessage(
                          id: 'draft',
                          senderId: 'draft',
                          senderName: 'draft',
                          receiverId: 'draft',
                          originalText: _input.text.trim(),
                          translatedText: _improved.trim(),
                          direction: MessageDirection.deafToBlind,
                          timestamp: DateTime.now(),
                          emotion: _emotion,
                        ),
                      )
                  : null,
              subtext: _emotion == null
                  ? 'Pick an emotion first'
                  : 'Your friend hears the emotion too',
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    super.dispose();
  }
}

class _EmotionChoice extends StatelessWidget {
  const _EmotionChoice({
    required this.emotion,
    required this.selected,
    required this.onTap,
  });

  final Emotion emotion;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Theme-aware palette, otherwise the label is unreadable on a dark surface.
    final Color color = emotion.colorFor(Theme.of(context).brightness);
    return ChoiceChip(
      avatar: Icon(emotion.icon, color: color, size: 26),
      label: Text(
        emotion.label.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 15,
          color: selected ? color : null,
        ),
      ),
      selected: selected,
      selectedColor: color.withValues(alpha: 0.18),
      checkmarkColor: color,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      labelPadding: const EdgeInsets.only(right: 8, left: 2),
      onSelected: (bool _) => onTap(),
    );
  }
}
