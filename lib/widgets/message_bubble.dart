import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import 'emotion_badge.dart';

/// One chat message. Deaf-oriented design: big readable text, clear bubbles,
/// emotion badge, explicit delivery status. Never sound-only.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  bool get _hasVoice => message.audioPath != null;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool simplified = message.direction == MessageDirection.blindToDeaf;

    final Color bubbleColor = isMine
        ? scheme.primary.withValues(alpha: 0.14)
        : scheme.surfaceContainerHighest;
    final Color borderColor = isMine
        ? scheme.primary.withValues(alpha: 0.45)
        : scheme.outlineVariant;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Header: who + emotion + status ----
            Row(
              children: [
                if (message.emotion != null) ...[
                  EmotionBadge(emotion: message.emotion!, compact: true),
                  const SizedBox(width: 6),
                ],
                if (isMine) ...[
                  const Spacer(),
                  _StatusChip(status: message.status),
                ],
              ],
            ),
            // ---- Main text: the translated/improved message ----
            const SizedBox(height: 6),
            SelectableText(
              message.displayText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
            ),
            // ---- Original text, clearly separated ----
            if (message.originalText.trim().isNotEmpty &&
                message.originalText.trim() != message.translatedText.trim())
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      simplified
                          ? Icons.record_voice_over_outlined
                          : Icons.keyboard_alt_outlined,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message.originalText,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            if (_hasVoice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.graphic_eq_rounded,
                      size: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Voice message',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final String hh = time.hour.toString().padLeft(2, '0');
    final String mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    switch (status) {
      case MessageStatus.sending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 13, color: scheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              'Pending',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case MessageStatus.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.done_all, size: 13, color: scheme.primary),
            const SizedBox(width: 3),
            Text(
              'Sent',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ],
        );
      case MessageStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 13, color: scheme.error),
            const SizedBox(width: 3),
            Text(
              'Not delivered',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: scheme.error,
              ),
            ),
          ],
        );
    }
  }
}
