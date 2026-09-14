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

  Future<void> configure({
    required double rate,
    required double pitch,
    required double volume,
  }) async {
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(volume);
    await _tts.setLanguage('en-US');
    _configured = true;
  }

  Future<void> _ensureConfigured() async {
    if (!_configured) {
      await configure(rate: 0.5, pitch: 1.0, volume: 1.0);
    }
  }

  /// Speaks [text]. Returns when the engine accepted the request.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureConfigured();
    await _tts.stop(); // Cut short any previous announcement.
    await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
  Future<void> pause() => _tts.pause();

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

  Future<void> dispose() => _tts.stop();
}
