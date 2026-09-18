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

  /// A readable version of this emotion's colour for the given theme.
  ///
  /// The base palette is chosen for light backgrounds; on a dark surface those
  /// mid-tone greens and blues fall to roughly 2.5:1 contrast, which is too low
  /// for the small emotion label - the one signal a deaf user relies on. On
  /// dark themes the colour is lifted instead.
  Color colorFor(Brightness brightness) {
    if (brightness == Brightness.light) return color;
    final HSLColor hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.34).clamp(0.0, 0.80))
        .withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0))
        .toColor();
  }

  /// Text spoken by TTS *before* the message body so the blind recipient
  /// hears the emotional tone, e.g. "Happy. I'm really glad you came today."
  String get spokenPrefix => '$label.';

  /// Stable name stored in the local database / JSON payloads.
  String get storageName => name;

  /// Looks up an emotion by its stored name, or returns **null** when the name
  /// is unknown.
  ///
  /// It MUST NOT fall back to a default. This app's whole promise is that an
  /// emotion is only ever the one the sender picked - returning [Emotion.happy]
  /// for a missing, corrupted or future value would make the blind recipient
  /// hear "Happy." for a feeling nobody chose.
  static Emotion? fromName(String? name) {
    if (name == null) return null;
    for (final Emotion emotion in Emotion.values) {
      if (emotion.name == name) return emotion;
    }
    return null;
  }
}
