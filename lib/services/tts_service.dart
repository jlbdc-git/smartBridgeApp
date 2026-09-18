import 'package:flutter_tts/flutter_tts.dart';

import '../models/chat_message.dart';
import '../models/emotion.dart';

/// Central text-to-speech facade for the blind user.
///
/// All spoken output goes through here so voice speed/pitch/volume settings
/// and the emotion announcement stay consistent across screens.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  /// Upper bound on a single utterance. Completion is awaited (see
  /// [configure]), so this is what guarantees a wedged TTS engine can never
  /// hang a caller or leave a "Speaking..." indicator stuck on screen.
  static const Duration speakTimeout = Duration(seconds: 45);

  /// Accessibility -> "Text-to-speech" switch. When false every [speak] call
  /// is a no-op so a blind user can silence the app completely.
  bool enabled = true;

  Future<void> configure({
    required double rate,
    required double pitch,
    required double volume,
  }) async {
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
      await _tts.setLanguage('en-US');
      // Make [speak] resolve when the utterance actually FINISHES rather than
      // when the engine merely accepted it. Without this the blind chat's
      // "Speaking..." indicator was cleared a few milliseconds after starting,
      // so the state shown to the user was simply wrong.
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    } catch (_) {
      // A missing/broken TTS engine must never crash the messaging flow.
    }
  }

  Future<void> _ensureConfigured() async {
    if (!_configured) {
      await configure(rate: 0.5, pitch: 1.0, volume: 1.0);
    }
  }

  /// Speaks [text]. Returns when the engine accepted the request.
  Future<void> speak(String text) async {
    if (!enabled) return;
    if (text.trim().isEmpty) return;
    await _ensureConfigured();
    try {
      await _tts.stop(); // Cut short any previous announcement.
      await _tts.speak(text).timeout(speakTimeout, onTimeout: () => null);
    } catch (_) {
      // Speaking is best effort; never break sending/reading because of it.
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {
      // Stop is best effort.
    }
  }

  Future<void> pause() async {
    try {
      await _tts.pause();
    } catch (_) {
      // Pause is best effort.
    }
  }

  /// Speaks a received message. The emotion is announced FIRST so the blind
  /// listener hears the tone: "Happy. I'm really glad you came today."
  Future<void> speakMessage(ChatMessage message) async {
    final Emotion? emotion = message.emotion;
    final String body = message.displayText;
    if (emotion != null) {
      await speak('${emotion.spokenPrefix} $body');
    } else {
      await speak(body);
    }
  }

  /// Short system confirmations: "Message sent", "New message from John".
  Future<void> speakConfirmation(String text) => speak(text);

  Future<void> dispose() => stop();
}
