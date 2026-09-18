import 'package:flutter/foundation.dart';

import 'emotion.dart';

/// Direction of a message: who used which translator.
enum MessageDirection { blindToDeaf, deafToBlind }

MessageDirection directionFromName(String? name) {
  return name == 'deafToBlind' ? MessageDirection.deafToBlind : MessageDirection.blindToDeaf;
}

/// Delivery state of a message in the offline-first outbox.
enum MessageStatus { sending, sent, failed }

MessageStatus statusFromName(String? name) {
  switch (name) {
    case 'failed':
      return MessageStatus.failed;
    case 'sending':
      return MessageStatus.sending;
    default:
      return MessageStatus.sent;
  }
}

/// A single chat message between two confirmed friends.
///
/// The message keeps BOTH the original input and the translated/improved text
/// so the chat can always show what was actually said vs. what was sent.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.originalText,
    required this.translatedText,
    required this.direction,
    required this.timestamp,
    this.emotion,
    this.status = MessageStatus.sent,
    this.readByReceiver = false,
    this.audioPath,
    this.transcription,
  });

  final String id;

  final String senderId;
  final String senderName;
  final String receiverId;

  /// Exactly what the user said/typed before translation.
  final String originalText;

  /// Simplified (blind sender) or improved (deaf sender) text that travels.
  final String translatedText;

  final MessageDirection direction;

  final DateTime timestamp;

  /// Manually chosen by a Deaf sender; null for blind senders.
  final Emotion? emotion;

  final MessageStatus status;

  final bool readByReceiver;

  /// For blind voice messages: local file where the raw audio was kept.
  final String? audioPath;

  /// Speech-to-text result of the voice message (== originalText for voice).
  final String? transcription;

  /// The text that is spoken by TTS / shown as the main bubble content.
  String get displayText => translatedText;

  ChatMessage copyWith({
    MessageStatus? status,
    bool? readByReceiver,
    String? senderId,
    String? receiverId,
    String? senderName,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      receiverId: receiverId ?? this.receiverId,
      originalText: originalText,
      translatedText: translatedText,
      direction: direction,
      timestamp: timestamp,
      emotion: emotion,
      status: status ?? this.status,
      readByReceiver: readByReceiver ?? this.readByReceiver,
      audioPath: audioPath,
      transcription: transcription,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': receiverId,
        'originalText': originalText,
        'translatedText': translatedText,
        'direction': direction.name,
        'timestamp': timestamp.toIso8601String(),
        'emotion': emotion?.storageName,
        'status': status.name,
        'readByReceiver': readByReceiver,
        'audioPath': audioPath,
        'transcription': transcription,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: (json['id'] ?? '') as String,
      senderId: (json['senderId'] ?? '') as String,
      senderName: (json['senderName'] ?? '') as String,
      receiverId: (json['receiverId'] ?? '') as String,
      originalText: (json['originalText'] ?? '') as String,
      translatedText: (json['translatedText'] ?? '') as String,
      direction: directionFromName(json['direction'] as String?),
      timestamp:
          DateTime.tryParse((json['timestamp'] ?? '') as String) ?? DateTime.now(),
      // Unknown/absent emotion stays null: never guess how someone felt.
      emotion: Emotion.fromName(json['emotion'] as String?),
      status: statusFromName(json['status'] as String?),
      readByReceiver: (json['readByReceiver'] ?? false) as bool,
      audioPath: json['audioPath'] as String?,
      transcription: json['transcription'] as String?,
    );
  }

  /// Wire format exchanged over the LAN transport.
  Map<String, dynamic> toWire() => toJson();

  factory ChatMessage.fromWire(Map<String, dynamic> json) =>
      ChatMessage.fromJson(json);
}
