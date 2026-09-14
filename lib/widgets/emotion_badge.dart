import 'package:flutter/material.dart';

import '../models/emotion.dart';

/// Small rounded badge showing the emotion icon + label, e.g. 😊 Happy.
/// Deaf mode relies on this visual indicator; it is never sound-only.
class EmotionBadge extends StatelessWidget {
  const EmotionBadge({
    super.key,
    required this.emotion,
    this.compact = false,
  });

  final Emotion emotion;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color color = emotion.color;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(emotion.icon, size: compact ? 14 : 17, color: color),
          const SizedBox(width: 4),
          Text(
            emotion.label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 11 : 13,
            ),
          ),
        ],
      ),
    );
  }
}
