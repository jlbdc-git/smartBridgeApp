import 'package:flutter/material.dart';

/// Original history page + item model (extracted unchanged).
class HistoryPage extends StatelessWidget {
  const HistoryPage({
    super.key,
    required this.history,
    required this.onClearHistory,
  });

  final List<HistoryItem> history;
  final VoidCallback onClearHistory;

  String _formatTime(DateTime time) {
    final String hh = time.hour.toString().padLeft(2, '0');
    final String mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'sign':
        return Icons.sign_language;
      case 'speech':
        return Icons.mic;
      case 'tts':
        return Icons.volume_up;
      default:
        return Icons.notes;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 54,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 10),
            const Text('No history yet.'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: IconButton(
              onPressed: onClearHistory,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear',
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: history.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final HistoryItem item = history[index];
              return Card(
                child: ListTile(
                  leading: Icon(_iconForType(item.type)),
                  title: Text(item.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_formatTime(item.timestamp)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}


class HistoryItem {
  HistoryItem({
    required this.type,
    required this.text,
    required this.timestamp,
    this.confidence,
  });

  final String type;
  final String text;
  final DateTime timestamp;
  final int? confidence;
}
