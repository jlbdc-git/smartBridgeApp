import 'dart:async';

import '../database/local_database.dart';
import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';
import 'tts_service.dart';
import 'transport/lan_transport.dart';

/// Chat orchestration: builds messages, stores them locally, delivers them
/// over the LAN transport when possible and replays the outbox when a friend
/// becomes reachable again.
///
/// OFFLINE-FIRST: every message is written to the local database BEFORE any
/// delivery attempt, so conversations always survive app restarts and lost
/// connections.
class ChatService {
  ChatService({
    required this.database,
    required this.transport,
    required this.tts,
  });

  final LocalDatabase database;
  final LanTransport transport;
  final TtsService tts;

  final StreamController<ChatMessage> _incoming =
      StreamController<ChatMessage>.broadcast();

  /// Emits messages received from friends.
  Stream<ChatMessage> get incomingMessages => _incoming.stream;

  final StreamController<String> _outboxEvents =
      StreamController<String>.broadcast();

  /// Emits message ids whose delivery state changed (for UI refresh).
  Stream<String> get outboxEvents => _outboxEvents.stream;

  UserProfile? _me;

  UserProfile? get me => _me;

  void setMe(UserProfile profile) {
    _me = profile;
    transport.updateIdentity(<String, dynamic>{
      'id': profile.id,
      'name': profile.name,
      'role': profile.role.name,
      'type': 'announce',
    });
  }

  // ---------------- Receiving ----------------

  /// Wires the transport events into the chat pipeline.
  void startListening() {
    transport.events.listen(_onTransportEvent);
  }

  Future<void> _onTransportEvent(Map<String, dynamic> event) async {
    if (event['type'] != 'chat') return;
    if (_me == null) return;

    final ChatMessage message = ChatMessage.fromWire(event);
    // Ignore messages that are not addressed to me or that I echo myself.
    if (message.receiverId != _me!.id) return;
    if (message.senderId == _me!.id) return;

    // Only accept messages from confirmed friends.
    if (database.findFriend(message.senderId) == null) return;

    // Idempotency: the same message may arrive twice (retry or broadcast).
    final List<ChatMessage> existing =
        database.loadMessages(message.senderId);
    if (existing.any((ChatMessage m) => m.id == message.id)) return;

    await database.upsertMessage(message.senderId, message);
    _incoming.add(message);
  }

  /// Marks a friend's messages as read (used when opening the chat screen).
  Future<void> markConversationRead(String friendId) async {
    final List<ChatMessage> messages = database
        .loadMessages(friendId)
        .map((ChatMessage m) =>
            m.senderId == friendId && !m.readByReceiver
                ? m.copyWith(readByReceiver: true)
                : m)
        .toList();
    await database.saveMessages(friendId, messages);
  }

  // ---------------- Sending ----------------

  /// Builds, stores and (best effort) delivers a message.
  Future<ChatMessage> sendMessage({
    required Friend friend,
    required String originalText,
    required String translatedText,
    required MessageDirection direction,
    Emotion? emotion,
    String? audioPath,
    String? transcription,
  }) async {
    final UserProfile me = _me!;
    final ChatMessage message = ChatMessage(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}-${me.id.hashCode.abs() % 9999}',
      senderId: me.id,
      senderName: me.name,
      receiverId: friend.id,
      originalText: originalText,
      translatedText: translatedText,
      direction: direction,
      timestamp: DateTime.now(),
      emotion: emotion,
      status: MessageStatus.sending,
      audioPath: audioPath,
      transcription: transcription,
    );

    // 1. Persist first (offline-first guarantee).
    await database.upsertMessage(friend.id, message);

    // 2. Best-effort delivery right now.
    final bool delivered = await _deliver(message);
    final ChatMessage stored = delivered
        ? message.copyWith(status: MessageStatus.sent)
        : message; // stays 'sending' => pending in the outbox

    await database.upsertMessage(friend.id, stored);
    _outboxEvents.add(stored.id);
    return stored;
  }

  Future<bool> _deliver(ChatMessage message) async {
    final Map<String, dynamic> wire = <String, dynamic>{
      ...message.toWire(),
      'type': 'chat',
    };
    return transport.sendToFriend(message.receiverId, wire);
  }

  /// Retries every pending message for [friendId] (e.g. friend came online).
  Future<void> retryPendingFor(String friendId) async {
    final List<ChatMessage> pending = database
        .loadMessages(friendId)
        .where((ChatMessage m) =>
            m.senderId == (_me?.id ?? '') && m.status != MessageStatus.sent)
        .toList();
    for (final ChatMessage message in pending) {
      final bool delivered = await _deliver(message);
      if (delivered) {
        await database.upsertMessage(
          friendId,
          message.copyWith(status: MessageStatus.sent),
        );
        _outboxEvents.add(message.id);
      }
    }
  }

  // ---------------- Blind-side reading ----------------

  /// Speaks a received message with its emotion prefix.
  Future<void> speakReceived(ChatMessage message) =>
      tts.speakMessage(message);

  Future<void> stopSpeaking() => tts.stop();

  void dispose() {
    _incoming.close();
    _outboxEvents.close();
  }
}
