import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../services/stt_service.dart';
import '../services/translation_service.dart';
import '../widgets/accessibility.dart';

/// BLIND pipeline: Voice -> Speech-to-Text -> simple/broken English ->
/// Preview -> Send.
///
/// The simplification is intentional (not grammar correction): short direct
/// sentences, minimal grammar, simple vocabulary. Meaning is preserved -
/// nothing is invented, nothing important is removed. If translation fails,
/// the original text is sent unchanged instead of losing the message.
class BlindTranslatorScreen extends StatefulWidget {
  const BlindTranslatorScreen({
    super.key,
    required this.session,
    required this.friendName,
    required this.friendId,
  });

  final SessionService session;
  final String friendName;
  final String friendId;

  @override
  State<BlindTranslatorScreen> createState() => _BlindTranslatorScreenState();
}

class _BlindTranslatorScreenState extends State<BlindTranslatorScreen> {
  final BlindTranslator _translator = const BlindTranslator();
  final SttService _stt = SttService();

  String _transcript = '';
  String _simplified = '';
  bool _listening = false;
  bool _sending = false;

  bool get _hasDraft => _simplified.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.session.tts.speakConfirmation(
        'Voice message to ${widget.friendName}. Tap the big button and speak.',
      );
    });
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _listening = true);

    final bool started = await _stt.start(
      onPartial: (String partialText) {
        if (!mounted) return;
        setState(() {
          _transcript = partialText;
          _simplified = _simplifySafely(partialText);
        });
      },
      onDone: (SpeechResult result) {
        if (!mounted) return;
        setState(() {
          _listening = false;
          _transcript = result.transcript;
          _simplified = _simplifySafely(result.transcript);
        });
        if (result.isEmpty) {
          widget.session.tts.speakConfirmation(
            "We couldn't understand the speech. Please try again.",
          );
        } else {
          widget.session.tts.speak(_simplified);
        }
      },
      onError: (String message) {
        if (!mounted) return;
        setState(() => _listening = false);
        widget.session.tts.speakConfirmation(message);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );

    if (!started && mounted) {
      setState(() => _listening = false);
    }
  }

  /// Translation failure fallback: keep the original text rather than
  /// deleting the message (spec 13).
  String _simplifySafely(String input) {
    try {
      return _translator.simplify(input);
    } catch (_) {
      return input;
    }
  }

  Future<void> _send() async {
    if (!_hasDraft || _sending) return;
    setState(() => _sending = true);

    final Friend? friend = widget.session.database.findFriend(widget.friendId);
    if (friend == null) {
      setState(() => _sending = false);
      await widget.session.tts.speakConfirmation(
        'This friend is no longer in your list.',
      );
      return;
    }

    await widget.session.chatService.sendMessage(
      friend: friend,
      originalText: _transcript,
      translatedText: _simplified,
      direction: MessageDirection.blindToDeaf,
    );

    setState(() => _sending = false);
    await widget.session.tts.speakConfirmation('Message sent.');

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _redo() async {
    setState(() {
      _transcript = '';
      _simplified = '';
    });
    await widget.session.tts.speakConfirmation('Cleared. Tap to speak again.');
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Voice message to ${widget.friendName}'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ---------------- Big microphone button ----------------
            Center(
              child: GestureDetector(
                onTap: _toggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _listening
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    border: Border.all(
                      color: _listening ? scheme.error : scheme.primary,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    _listening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 62,
                    color: _listening ? scheme.error : scheme.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                _listening ? 'Listening... tap to stop' : 'Tap to speak',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // ---------------- What you said ----------------
            PreviewCard(
              title: 'WHAT YOU SAID',
              body: _transcript.isEmpty
                  ? 'Your words appear here'
                  : _transcript,
            ),
            const SizedBox(height: 12),
            // ---------------- Simplified preview ----------------
            PreviewCard(
              title: 'WHAT WILL BE SENT (SIMPLIFIED)',
              body: _simplified.isEmpty
                  ? 'The simple version appears here'
                  : _simplified,
            ),
            const SizedBox(height: 20),
            BigButton(
              label: 'Send message',
              icon: Icons.send_rounded,
              onPressed: _hasDraft && !_sending ? _send : null,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _hasDraft ? _redo : null,
              icon: const Icon(Icons.refresh_rounded, size: 26),
              label: const Text(
                'Start over',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your meaning is kept. Only the wording gets simpler.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
