import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'permission_handler.dart';

/// Result of one speech recognition session.
class SpeechResult {
  const SpeechResult({required this.transcript, required this.confidence});

  final String transcript;
  final double confidence;

  bool get isEmpty => transcript.trim().isEmpty;
}

/// Speech-to-text wrapper for the blind user's voice input.
///
/// Microphone permission is requested lazily, only when the user starts a
/// voice message (see Privacy: request permissions only when required).
class SttService {
  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _initialized = false;
  bool get isListening => _listening;
  bool _listening = false;

  /// Prepares the recognizer. Returns false when speech recognition is not
  /// available on this device (or the OS reports it disabled).
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (Object error) => _listening = false,
        onStatus: (String status) {
          if (status == 'notListening' || status == 'done') {
            _listening = false;
          }
        },
      );
    } catch (_) {
      _initialized = false;
    }
    return _initialized;
  }

  /// Requests microphone permission (if needed) and starts listening.
  /// Returns false when permission is denied or the recognizer is unavailable.
  Future<bool> start({
    required void Function(String partialText) onPartial,
    required void Function(SpeechResult finalResult) onDone,
    required void Function(String message) onError,
  }) async {
    final bool micGranted = await PermissionHandler.requestMicrophonePermission();
    if (!micGranted) {
      onError('Microphone permission is required for voice messages.');
      return false;
    }

    final bool available = await initialize();
    if (!available) {
      onError(
        'Speech recognition is not available on this device. Please try again.',
      );
      return false;
    }

    try {
      _listening = true;
      await _speech.listen(
        // The parameter type is inferred from the plugin signature.
        onResult: (result) {
          final SpeechResult wrapped = SpeechResult(
            transcript: result.recognizedWords,
            confidence: result.confidence,
          );
          if (result.finalResult) {
            _listening = false;
            onDone(wrapped);
          } else {
            onPartial(wrapped.transcript);
          }
        },
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
        ),
        localeId: 'en_US',
      );
      return true;
    } catch (_) {
      _listening = false;
      onError('We couldn\'t understand the speech. Please try again.');
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _speech.stop();
    } catch (_) {
      // Stop is best effort.
    }
    _listening = false;
  }

  Future<void> cancel() async {
    try {
      await _speech.cancel();
    } catch (_) {
      // Cancel is best effort.
    }
    _listening = false;
  }
}
