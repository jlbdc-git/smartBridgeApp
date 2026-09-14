import 'package:flutter/material.dart';

/// Emotions a Deaf user can manually attach to an outgoing message.
///
/// IMPORTANT: emotions are ALWAYS chosen by the user. The app never tries to
/// infer, detect or diagnose the user's emotional state.
enum Emotion {
  happy,
  sad,
  angry,
  shy;

  /// Human readable label, e.g. "Happy".
  String get label {
    switch (this) {
      case Emotion.happy:
        return 'Happy';
      case Emotion.sad:
        return 'Sad';
      case Emotion.angry:
        return 'Angry';
      case Emotion.shy:
        return 'Shy';
    }
  }

  /// Material icon representing the emotion.
  IconData get icon {
    switch (this) {
      case Emotion.happy:
        return Icons.sentiment_very_satisfied;
      case Emotion.sad:
        return Icons.sentiment_very_dissatisfied;
      case Emotion.angry:
        return Icons.mood_bad;
      case Emotion.shy:
        return Icons.sentiment_neutral;
    }
  }

  /// Colour used for the emotion badge / bubble accent.
  Color get color {
    switch (this) {
      case Emotion.happy:
        return const Color(0xFF2E7D32); // green
      case Emotion.sad:
        return const Color(0xFF1565C0); // blue
      case Emotion.angry:
        return const Color(0xFFC62828); // red
      case Emotion.shy:
        return const Color(0xFF8E24AA); // purple
    }
  }

  /// Text spoken by TTS *before* the message body so the blind recipient
  /// hears the emotional tone, e.g. "Happy. I'm really glad you came today."
  String get spokenPrefix => '$label.';

  /// Stable name stored in the local database / JSON payloads.
  String get storageName => name;

  static Emotion fromName(String? name) {
    return Emotion.values.firstWhere(
      (Emotion e) => e.name == name,
      orElse: () => Emotion.happy,
    );
  }
}
