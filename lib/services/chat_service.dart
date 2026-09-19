import 'dart:async';

import '../backend/remote_backend.dart';
import '../database/local_database.dart';
import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';
import 'sample_friend.dart';
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
  final ChatTransport transport;
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

  /// Optional hook used to push a local "conversation read" to the internet
  /// backend, so the sender's device also shows it as read. Null when the app
  /// has no backend configured.
  Future<void> Function(String friendId)? readSyncHook;

  /// Optional provider for the current invite code. LAN announces carry it so
  /// a friend who connected with a TYPED code can be resolved to the real
  /// identity as soon as both devices are on the same Wi-Fi.
  String? Function()? inviteCodeProvider;

  /// The announce payload describing this user (id, name, role, invite code).
  Map<String, dynamic> _identityFor(UserProfile profile) {
    return <String, dynamic>{
      'id': profile.id,
      'name': profile.name,
      'role': profile.role.name,
      'code': inviteCodeProvider?.call(),
      'type': 'announce',
    };
  }

  /// Current announce identity (used when starting the transport).
  Map<String, dynamic> currentIdentity() {
    final UserProfile? me = _me;
    return me == null
        ? <String, dynamic>{'type': 'announce'}
        : _identityFor(me);
  }

  void setMe(UserProfile profile) {
    _me = profile;
    transport.updateIdentity(_identityFor(profile));
  }

  /// Built-in TEST/SAMPLE friend used for single-device testing.
  late final SampleFriendService sampleFriend = SampleFriendService(
    database: database,
    onLocalMessage: _acceptLocalIncoming,
  );

  /// Stores a locally generated message (from the sample friend) and fans it
  /// out exactly like a message that arrived over the network.
  Future<void> _acceptLocalIncoming(ChatMessage message) async {
    await database.upsertMessage(message.senderId, message);
    _incoming.add(message);
  }

  // ---------------- Receiving ----------------

  /// Wires the transport events into the chat pipeline.
  void startListening() {
    transport.events.listen(handleTransportEvent);
  }

  /// Handles one LAN event: chat delivery, and announces that (a) flush our
  /// pending outbox now that the friend is reachable and (b) resolve a
  /// typed-code friend entry to the real identity.
  Future<void> handleTransportEvent(Map<String, dynamic> event) async {
    final String type = event['type'] as String? ?? '';
    if (_me == null) return;

    if (type == 'announce') {
      final String? peerId = event['id'] as String?;
      if (peerId == null || peerId.isEmpty || peerId == _me!.id) return;

      // A typed-code entry cannot chat until we learn the real id.
      await _resolveTypedCode(peerId, event);

      // The friend is online: deliver everything still marked pending.
      if (database.findFriend(peerId) != null) {
        await retryPendingFor(peerId);
      }
      return;
    }

    if (type != 'chat') return;

    final ChatMessage incoming = ChatMessage.fromWire(event);
    // Ignore messages that are not addressed to me or that I echo myself.
    if (incoming.receiverId != _me!.id) return;
    if (incoming.senderId == _me!.id) return;

    // A message can be addressed with the sender's BACKEND id (internet
    // transport) instead of their local friend id, so resolve either way.
    final Friend? friend = database.findFriend(incoming.senderId) ??
        database.findFriendByRemoteId(incoming.senderId);
    // Only accept messages from confirmed friends.
    if (friend == null) return;

    // Normalise onto the local friend id so the message lands in the right
    // conversation whatever route it arrived by.
    final ChatMessage message = incoming.senderId == friend.id
        ? incoming
        : incoming.copyWith(senderId: friend.id, senderName: friend.name);

    // Idempotency: the same message may arrive twice (retry, retry after a
    // lost response, or both LAN and internet delivery).
    final List<ChatMessage> existing = database.loadMessages(friend.id);
    if (existing.any((ChatMessage m) => m.id == message.id)) return;

    await database.upsertMessage(friend.id, message);
    _incoming.add(message);

    // They are clearly online right now: push our own pending messages too.
    await retryPendingFor(friend.id);
  }

  /// Completes the typed-code flow: when the peer behind 'code:SB-XXXX-XX'
  /// announces itself with that code, swap the placeholder entry for the real
  /// identity (never for a user the tester removed before) and carry any
  /// messages already queued under the placeholder across.
  Future<void> _resolveTypedCode(
    String realId,
    Map<String, dynamic> announce,
  ) async {
    final Object? code = announce['code'];
    if (code is! String || code.isEmpty) return;

    final Friend? staged = database.findFriend('code:$code');
    if (staged == null) return;
    if (database.findFriend(realId) != null) {
      // Already resolved (or a real friend with the same id): drop the
      // placeholder and keep the real entry.
      await _dropFriendEntry('code:$code');
      return;
    }
    // Note: this only ever runs for a placeholder the user explicitly typed
    // AND confirmed, so re-connecting with a previously removed friend stays
    // possible; nothing is ever added without that explicit confirmation.

    final Object? name = announce['name'];
    final Friend resolved = Friend(
      id: realId,
      name: name is String && name.trim().isNotEmpty ? name.trim() : staged.name,
      role: roleFromName(announce['role'] as String?),
      addedAt: staged.addedAt,
    );

    // Replace the placeholder in one save (no blocklist side effects).
    final List<Friend> friends = database
        .loadFriends()
        .where((Friend f) => f.id != staged.id && f.id != realId)
        .toList()
      ..add(resolved);
    await database.saveFriends(friends);

    // Carry queued messages across to the real conversation key.
    for (final ChatMessage message in database.loadMessages(staged.id)) {
      await database.upsertMessage(
        realId,
        message.copyWith(receiverId: realId),
      );
    }
    await database.clearMessages(staged.id);
  }

  Future<void> _dropFriendEntry(String friendId) async {
    await database.saveFriends(
      database.loadFriends().where((Friend f) => f.id != friendId).toList(),
    );
    await database.clearMessages(friendId);
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
    // Best effort: share the read status over the internet backend too, so the
    // sender's device agrees. Never blocks the local update.
    final Future<void> Function(String)? hook = readSyncHook;
    if (hook != null) await hook(friendId);
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
    final UserProfile? me = _me;
    if (me == null) {
      // Defensive: sending without an identity means the session was never
      // wired up; fail clearly instead of crashing on a null check.
      throw StateError('ChatService.sendMessage called before setMe().');
    }
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

    // 2. Best-effort delivery right now. The built-in sample friend counts as
    //    delivered locally (its replies are generated on this device).
    bool delivered = false;
    if (sampleFriend.isSampleFriend(friend.id)) {
      delivered = true;
    } else if (friend.connectionStatus != ConnectionStatus.accepted) {
      // Friend request not accepted yet: the backend would (correctly) refuse
      // the insert, so do not even try. The message stays pending and will
      // deliver automatically once the request is accepted.
      delivered = false;
    } else {
      try {
        delivered = await _deliver(message);
      } on PolicyRefusalException {
        // This device believed the friendship was confirmed, but the server
        // disagrees (e.g. the other side removed and re-requested). Demote to
        // pending; the message stays queued.
        delivered = false;
        await _markPending(friend.id);
      }
    }
    final ChatMessage stored = delivered
        ? message.copyWith(status: MessageStatus.sent)
        : message; // stays 'sending' => pending in the outbox

    await database.upsertMessage(friend.id, stored);
    _outboxEvents.add(stored.id);

    // 3. The sample friend answers a moment later, like a real person would.
    sampleFriend.scheduleReply(me, friend);
    return stored;
  }

  Future<bool> _deliver(ChatMessage message) async {
    // Privacy guard: the sample friend is local-only, never sent on the wire.
    if (sampleFriend.isSampleFriend(message.receiverId)) return false;
    final Map<String, dynamic> wire = <String, dynamic>{
      ...message.toWire(),
      'type': 'chat',
    };
    return transport.sendToFriend(message.receiverId, wire);
  }

  /// Retries every pending message for [friendId] (e.g. friend came online).
  Future<void> retryPendingFor(String friendId) async {
    if (sampleFriend.isSampleFriend(friendId)) return;
    final Friend? friend = database.findFriend(friendId);
    // Not accepted yet: retrying now would just hit the RLS refusal again.
    if (friend == null ||
        friend.connectionStatus != ConnectionStatus.accepted) {
      return;
    }
    final List<ChatMessage> pending = database
        .loadMessages(friendId)
        .where((ChatMessage m) =>
            m.senderId == (_me?.id ?? '') && m.status != MessageStatus.sent)
        .toList();
    for (final ChatMessage message in pending) {
      bool delivered = false;
      try {
        delivered = await _deliver(message);
      } on PolicyRefusalException {
        // The server says the friendship is not confirmed (e.g. this device
        // still believed the old "instant friend" flow). Flip the link to
        // pending; the message stays queued and delivers after acceptance.
        delivered = false;
        await _markPending(friendId);
      }
      if (delivered) {
        await database.upsertMessage(
          friendId,
          message.copyWith(status: MessageStatus.sent),
        );
        _outboxEvents.add(message.id);
      }
    }
  }

  /// Demotes a friend link to pending (the server refused a write because the
  /// friendship is not confirmed). Returns true when the state changed, so
  /// the UI can be refreshed exactly once instead of on every refusal.
  Future<bool> _markPending(String friendId) async {
    final Friend? friend = database.findFriend(friendId);
    if (friend == null ||
        friend.connectionStatus == ConnectionStatus.pending) {
      return false;
    }
    await database.addFriend(
      friend.copyWith(connectionStatus: ConnectionStatus.pending),
    );
    return true;
  }

  // ---------------- Blind-side reading ----------------

  /// Speaks a received message with its emotion prefix.
  Future<void> speakReceived(ChatMessage message) =>
      tts.speakMessage(message);

  Future<void> stopSpeaking() => tts.stop();

  void dispose() {
    sampleFriend.dispose();
    _incoming.close();
    _outboxEvents.close();
  }
}
