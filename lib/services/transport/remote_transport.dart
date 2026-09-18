import 'dart:async';

import '../../backend/remote_backend.dart';
import '../../database/local_database.dart';
import '../../models/chat_message.dart';
import '../../models/user_profile.dart';
import 'lan_transport.dart';

/// Exposes the internet backend through the same [ChatTransport] contract the
/// LAN transport uses, so `ChatService` (and its offline outbox) needed no
/// knowledge of the cloud at all.
///
/// RESPONSIBILITY SPLIT
///  * [RemoteBackend] speaks in backend user ids (Supabase `auth.uid()`).
///  * This class translates those to and from the LOCAL friend ids used by the
///    local database, and re-emits everything as the transport wire format.
///
/// A friend only becomes reachable over the internet once their backend id is
/// known, which happens when they are connected through the QR/code flow while
/// both builds are backend-enabled. LAN-only friends keep working exactly as
/// before.
class RemoteTransport implements ChatTransport {
  RemoteTransport({required this.backend, required this.database});

  final RemoteBackend backend;
  final LocalDatabase database;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  StreamSubscription<ChatMessage>? _incomingSub;
  StreamSubscription<String>? _onlineSub;
  StreamSubscription<BackendState>? _stateSub;

  /// The announce payload ChatService gave us (local id, name, role, code).
  Map<String, dynamic> _identity = <String, dynamic>{};

  bool _started = false;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// My local profile id, learned from the announce identity.
  String? get _myLocalId => _identity['id'] as String?;

  /// Starts the backend (if configured) and bridges its streams.
  Future<void> start(Map<String, dynamic> identity) async {
    _identity = identity;
    if (_started) return;
    _started = true;

    _incomingSub = backend.incomingMessages.listen(_onRemoteMessage);
    _onlineSub = backend.friendsOnline.listen(_onFriendOnline);
    // The backend retries on its own after a failure. Re-publishing when it
    // recovers is what makes a phone that was offline at launch (so its invite
    // code never reached the server) usable as soon as the network is back.
    _stateSub = backend.stateChanges.listen((BackendState state) {
      if (state == BackendState.ready) unawaited(_publishProfile());
    });

    await backend.initialize();
    await _publishProfile();
  }

  @override
  void updateIdentity(Map<String, dynamic> identity) {
    _identity = identity;
    unawaited(_publishProfile());
  }

  /// Mirrors this user's name / role / current invite code to the backend, so
  /// a friend who scans the code can resolve the real identity.
  Future<void> _publishProfile() async {
    if (!_started) return;
    final String? name = _identity['name'] as String?;
    if (name == null || name.isEmpty) return;
    final Object? code = _identity['code'];
    await backend.publishProfile(
      displayName: name,
      role: roleFromName(_identity['role'] as String?),
      inviteCode: code is String && code.isNotEmpty ? code : null,
    );
  }

  /// True when this friend can currently be reached over the internet.
  bool canReach(Friend friend) =>
      friend.remoteId != null && backend.state == BackendState.ready;

  // ---------------- Sending ----------------

  @override
  Future<bool> sendToFriend(
    String friendId,
    Map<String, dynamic> payload,
  ) async {
    final Friend? friend = database.findFriend(friendId);
    if (friend == null) return false;
    final String? remoteId = friend.remoteId;
    // No backend identity for this friend: the LAN transport (or the outbox)
    // is responsible. Reporting false keeps the message pending.
    if (remoteId == null) return false;
    if (backend.state != BackendState.ready) return false;

    final ChatMessage message = ChatMessage.fromWire(payload);
    // Stamp the wire fields the server needs, keeping the local ids intact for
    // the local copy.
    return backend.sendMessage(
      ChatMessage(
        id: message.id,
        senderId: message.senderId,
        senderName: message.senderName,
        receiverId: message.receiverId,
        originalText: message.originalText,
        translatedText: message.translatedText,
        direction: message.direction,
        timestamp: message.timestamp,
        emotion: message.emotion,
        status: message.status,
        readByReceiver: message.readByReceiver,
        audioPath: message.audioPath,
        transcription: message.transcription,
      ),
      toRemoteUserId: remoteId,
    );
  }

  // ---------------- Receiving ----------------

  void _onRemoteMessage(ChatMessage remote) {
    final String? myLocalId = _myLocalId;
    if (myLocalId == null) return;

    // Route the backend sender id back to the local friend record.
    final Friend? friend = database.findFriendByRemoteId(remote.senderId);
    if (friend == null) return; // not a confirmed local friend: ignore

    // Re-emit with LOCAL ids so the rest of the app is unaware of the cloud.
    final ChatMessage local = ChatMessage(
      id: remote.id,
      senderId: friend.id,
      senderName: friend.name,
      receiverId: myLocalId,
      originalText: remote.originalText,
      translatedText: remote.translatedText,
      direction: remote.direction,
      timestamp: remote.timestamp,
      emotion: remote.emotion,
      status: MessageStatus.sent,
      readByReceiver: remote.readByReceiver,
      transcription: remote.transcription,
    );

    _events.add(<String, dynamic>{
      ...local.toWire(),
      'type': 'chat',
    });
    // Sharing a message proves the friend is online: let the outbox flush.
    _events.add(<String, dynamic>{
      'type': 'announce',
      'id': friend.id,
      'name': friend.name,
      'role': friend.role.name,
    });
  }

  /// A configured friend's heartbeat was seen: announce them so pending
  /// messages flush, exactly like the LAN announce does.
  void _onFriendOnline(String remoteUserId) {
    final Friend? friend = database.findFriendByRemoteId(remoteUserId);
    if (friend == null) return;
    _events.add(<String, dynamic>{
      'type': 'announce',
      'id': friend.id,
      'name': friend.name,
      'role': friend.role.name,
    });
  }

  // ---------------- Read receipts ----------------

  /// Pushes a local "conversation read" to the backend so the sender's device
  /// shows it read too. Best effort.
  Future<void> markConversationRead(String friendId) async {
    final Friend? friend = database.findFriend(friendId);
    final String? remoteId = friend?.remoteId;
    if (remoteId == null) return;
    await backend.markConversationRead(remoteId);
  }

  /// Ends the friendship on the backend (used when a friend is removed).
  Future<void> revoke(String friendId) async {
    final Friend? friend = database.findFriend(friendId);
    final String? remoteId = friend?.remoteId;
    if (remoteId == null) return;
    await backend.revokeFriendship(remoteId);
  }

  void dispose() {
    _incomingSub?.cancel();
    _onlineSub?.cancel();
    _stateSub?.cancel();
    _events.close();
  }
}
