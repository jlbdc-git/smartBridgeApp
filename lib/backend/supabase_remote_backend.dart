import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';
import 'remote_backend.dart';

/// Supabase implementation of [RemoteBackend] - the internet transport that
/// lets two confirmed friends talk across different networks.
///
/// ARCHITECTURE
/// ```
/// User A -> internet -> Supabase (Postgres + Realtime) -> internet -> User B
/// ```
/// The QR/short-code flow stays the only way to create a friendship, but the
/// codes are now looked up **on the server** with an exact-match only RPC, so
/// there is still no directory and no search.
///
/// SAFETY RULES BAKED IN
///  * This class NEVER throws. Every failure degrades to `false`/`null` and a
///    [BackendState.error], because the app must keep working offline.
///  * Only an anonymous session is used: no emails, no passwords, no phone
///    numbers are ever collected (the spec forbids unnecessary personal data).
///  * Row level security - not this code - is what stops a user reading
///    somebody else's data. See `supabase/policies.sql`.
///  * Presence is a `last_seen_at` heartbeat on the user's own profile row
///    rather than a realtime presence channel, so "is my friend online?" is
///    answerable even right after a cold start, and it reuses the same RLS
///    rules as everything else.
class SupabaseRemoteBackend implements RemoteBackend {
  SupabaseRemoteBackend({
    required this.client,
    required this.friendRemoteIds,
  });

  final SupabaseClient client;

  /// Supplies the backend user ids of this user's confirmed friends. Injected
  /// as a callback so the backend never depends on the local database.
  final Set<String> Function() friendRemoteIds;

  /// A friend is considered reachable if their heartbeat is younger than this.
  /// Must comfortably exceed [heartbeatInterval] to survive one missed beat.
  static const Duration onlineWindow = Duration(seconds: 75);

  /// How often this device says "I am still here".
  static const Duration heartbeatInterval = Duration(seconds: 25);

  BackendState _state = BackendState.connecting;
  String? _uid;
  String? _lastError;
  bool _disposed = false;

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _friendshipsChannel;
  RealtimeChannel? _profilesChannel;
  Timer? _heartbeat;
  Timer? _reconnect;

  final StreamController<BackendState> _states =
      StreamController<BackendState>.broadcast();
  final StreamController<ChatMessage> _incoming =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _online =
      StreamController<String>.broadcast();
  final StreamController<RemoteRequest> _requests =
      StreamController<RemoteRequest>.broadcast();
  final StreamController<RemoteFriendship> _friendshipUpdates =
      StreamController<RemoteFriendship>.broadcast();

  @override
  BackendState get state => _state;

  @override
  String? get userId => _uid;

  @override
  String? get lastError => _lastError;

  @override
  Stream<BackendState> get stateChanges => _states.stream;

  @override
  Stream<ChatMessage> get incomingMessages => _incoming.stream;

  @override
  Stream<String> get friendsOnline => _online.stream;

  @override
  Stream<RemoteRequest> get incomingRequests => _requests.stream;

  @override
  Stream<RemoteFriendship> get friendshipUpdates => _friendshipUpdates.stream;

  // ---------------- Lifecycle ----------------

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    _setState(BackendState.connecting);
    try {
      // Anonymous sign-in keeps the identity stable across restarts while
      // collecting nothing personal. An existing session is reused.
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }
      _uid = client.auth.currentUser?.id;
      if (_uid == null) {
        _fail('Could not establish a backend identity.');
        return;
      }
      _lastError = null;
      await _subscribe();
      _startHeartbeat();
      _setState(BackendState.ready);
      await _announceOnlineFriends();
    } on AuthException catch (e) {
      // Anonymous sign-in disabled in the Supabase project, or bad key.
      _fail('Sign-in failed: ${e.message}');
    } catch (e) {
      // Offline, DNS failure, project paused... all recoverable.
      _fail('Cannot reach the backend: $e');
    }
  }

  Future<void> _subscribe() async {
    await _messagesChannel?.unsubscribe();
    await _friendshipsChannel?.unsubscribe();
    await _profilesChannel?.unsubscribe();

    final String uid = _uid!;

    // Realtime authorises each subscription with the CURRENT access token.
    // `SupabaseClient` pushes the token on sign-in events, but that push is
    // fire-and-forget (unawaited upstream), so it can race the first
    // subscribe after a cold start. Push it explicitly and await it so the
    // join payload always carries a fresh, authenticated JWT.
    try {
      await client.realtime.setAuth(
        client.auth.currentSession?.accessToken,
      );
    } catch (_) {
      // Not fatal: the socket may already carry a valid token from the
      // supabase_flutter listener. Individual channel statuses below will
      // still surface an auth rejection.
    }

    // Status callback shared by all three channels. A rejected subscription
    // (RLS grant missing, filter validation failed, token stale) must be
    // VISIBLE, not silently swallowed - otherwise the app looks ready while
    // no live updates ever arrive.
    void onChannelStatus(String name, RealtimeSubscribeStatus status,
        Object? error) {
      if (_disposed) return;
      switch (status) {
        case RealtimeSubscribeStatus.subscribed:
          _lastError = null;
        case RealtimeSubscribeStatus.channelError:
        case RealtimeSubscribeStatus.timedOut:
          _noteFailure(
            'Realtime channel "$name" failed: ${error ?? status.name}',
          );
        case RealtimeSubscribeStatus.closed:
          // Normal when we unsubscribe ourselves; only note it mid-session.
          if (_state == BackendState.ready) {
            _noteFailure('Realtime channel "$name" closed unexpectedly.');
          }
      }
    }

    // 1. New messages addressed to me.
    _messagesChannel = client
        .channel('sb-messages-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (PostgresChangePayload payload) {
            final ChatMessage? message = _messageFromRow(payload.newRecord);
            if (message != null) _incoming.add(message);
          },
        )
        .subscribe(
          (status, error) => onChannelStatus('messages', status, error),
        );

    // 2. Friendships addressed to me. INSERT = an inbound friend request;
    //    UPDATE = the row changed behind my back (my outgoing request was
    //    accepted, or was declined by the addressee).
    _friendshipsChannel = client
        .channel('sb-friendships-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friendships',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'addressee_id',
            value: uid,
          ),
          callback: (PostgresChangePayload payload) {
            unawaited(_onFriendshipInsert(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friendships',
          callback: (PostgresChangePayload payload) {
            unawaited(_onFriendshipUpdate(payload.newRecord, payload.oldRecord));
          },
        )
        .subscribe(
          (status, error) => onChannelStatus('friendships', status, error),
        );

    // 3. Friends' profile heartbeats. RLS means this only ever delivers rows
    //    for me and my confirmed friends, so no client-side filtering of
    //    strangers is possible (there are none).
    _profilesChannel = client
        .channel('sb-profiles-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (PostgresChangePayload payload) {
            final Map<String, dynamic> row = payload.newRecord;
            final Object? id = row['id'];
            if (id is! String || id == uid) return;
            if (!friendRemoteIds().contains(id)) return;
            if (_isRecentlySeen(row['last_seen_at'])) _online.add(id);
          },
        )
        .subscribe(
          (status, error) => onChannelStatus('profiles', status, error),
        );
  }

  Future<void> _onFriendshipInsert(Map<String, dynamic> row) async {
    final Object? friendshipId = row['id'];
    final Object? requester = row['requester_id'];
    if (friendshipId is! String || requester is! String) return;
    // Only genuinely inbound requests are interesting.
    if (requester == _uid) return;
    if (row['status'] != 'pending') return;

    final RemotePeer? peer = await _fetchPeer(requester);
    if (peer == null) return;
    _requests.add(
      RemoteRequest(friendshipId: friendshipId, peer: peer),
    );
  }

  /// My OUTGOING request was accepted or declined on the other device.
  /// [oldRecord] carries the previous status (realtime UPDATE payloads only
  /// include the old row when REPLICA IDENTITY is set; when it is empty the
  /// client just refreshes its whole request list, which is safe).
  Future<void> _onFriendshipUpdate(
    Map<String, dynamic> row,
    Map<String, dynamic> oldRecord,
  ) async {
    final Object? id = row['id'];
    if (id is! String) return;
    final Object? requester = row['requester_id'];
    // Only rows where I am the requester reach this client (the realtime
    // SELECT policy filters by participant), so an update here is about a
    // request I sent.
    if (requester is String && requester != _uid) return;

    final RemoteFriendshipStatus? status =
        friendshipStatusFromName(row['status']?.toString());
    if (status == null) return;

    final RemotePeer? peer = await _fetchPeer(
      row['addressee_id']?.toString() ?? '',
    );
    if (peer == null) return;

    _friendshipUpdates.add(
      RemoteFriendship(
        friendshipId: id,
        incoming: false,
        status: status,
        peer: peer,
      ),
    );
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    unawaited(_beat());
    _heartbeat = Timer.periodic(
      heartbeatInterval,
      (Timer _) => unawaited(_beat()),
    );
  }

  Future<void> _beat() async {
    final String? uid = _uid;
    if (uid == null || _disposed) return;
    try {
      await client
          .from('profiles')
          .update(<String, dynamic>{'last_seen_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', uid);
    } catch (_) {
      // A dropped heartbeat is not worth surfacing: the next one retries.
    }
  }

  /// Reports which friends are already online when the app starts, instead of
  /// waiting for their next heartbeat.
  Future<void> _announceOnlineFriends() async {
    final Set<String> ids = friendRemoteIds();
    if (ids.isEmpty) return;
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('profiles')
          .select('id, last_seen_at')
          .inFilter('id', ids.toList());
      for (final Map<String, dynamic> row in rows) {
        final Object? id = row['id'];
        if (id is String && _isRecentlySeen(row['last_seen_at'])) {
          _online.add(id);
        }
      }
    } catch (_) {
      // Offline: the outbox simply keeps its messages until later.
    }
  }

  static bool _isRecentlySeen(Object? value) {
    if (value is! String) return false;
    final DateTime? seen = DateTime.tryParse(value);
    if (seen == null) return false;
    return DateTime.now().toUtc().difference(seen.toUtc()) < onlineWindow;
  }

  // ---------------- Profile ----------------

  @override
  Future<bool> publishProfile({
    required String displayName,
    required UserRole role,
    String? inviteCode,
  }) async {
    final String? uid = _uid;
    if (uid == null) return false;
    try {
      final Map<String, dynamic> row = <String, dynamic>{
        'id': uid,
        'display_name': displayName,
        'role': role.name,
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        if (inviteCode != null) ...<String, dynamic>{
          'invite_code': inviteCode,
          'invite_issued_at': DateTime.now().toUtc().toIso8601String(),
        },
      };
      await client.from('profiles').upsert(row);
      return true;
    } catch (e) {
      _noteFailure(e);
      return false;
    }
  }

  // ---------------- Friend connection ----------------

  @override
  Future<RemotePeer?> lookupInviteCode(String code) async {
    try {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'lookup_invite_code',
        <String, dynamic>{'p_code': code},
      );
      if (rows.isEmpty) return null;
      return _peerFromRow(rows.first);
    } catch (e) {
      _noteFailure(e);
      return null;
    }
  }

  @override
  Future<RemoteRequestOutcome?> requestFriendship(String code) async {
    try {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'request_friendship',
        <String, dynamic>{'p_code': code},
      );
      if (rows.isEmpty) return null;
      final RemotePeer? peer = _peerFromRow(rows.first);
      if (peer == null) return null;
      final bool confirmed = rows.first['status']?.toString() == 'confirmed';
      return RemoteRequestOutcome(peer: peer, confirmed: confirmed);
    } catch (e) {
      _noteFailure(e);
      return null;
    }
  }

  @override
  Future<bool> confirmFriendship(String friendshipId) async {
    try {
      await client.rpc<dynamic>(
        'confirm_friendship',
        params: <String, dynamic>{'p_friendship_id': friendshipId},
      );
      return true;
    } catch (e) {
      _noteFailure(e);
      return false;
    }
  }

  @override
  Future<bool> declineFriendship(String friendshipId) async {
    try {
      await client.rpc<dynamic>(
        'decline_friendship',
        params: <String, dynamic>{'p_friendship_id': friendshipId},
      );
      return true;
    } catch (e) {
      _noteFailure(e);
      return false;
    }
  }

  @override
  Future<List<RemoteFriendship>> listMyRequests() async {
    try {
      final List<Map<String, dynamic>> rows = await _rpcRows(
        'list_my_requests',
        <String, dynamic>{},
      );
      final List<RemoteFriendship> requests = <RemoteFriendship>[];
      for (final Map<String, dynamic> row in rows) {
        final Object? id = row['friendship_id'];
        final Object? peerId = row['peer_id'];
        final RemoteFriendshipStatus? status =
            friendshipStatusFromName(row['status']?.toString());
        if (id is! String || peerId is! String || status == null) continue;
        requests.add(
          RemoteFriendship(
            friendshipId: id,
            incoming: row['direction']?.toString() == 'incoming',
            status: status,
            peer: RemotePeer(
              userId: peerId,
              displayName: row['peer_name']?.toString() ?? 'Friend',
              role: roleFromName(row['peer_role']?.toString()),
            ),
          ),
        );
      }
      return requests;
    } catch (e) {
      _noteFailure(e);
      return const <RemoteFriendship>[];
    }
  }

  @override
  Future<void> revokeFriendship(String friendUserId) async {
    try {
      await client.rpc<dynamic>(
        'revoke_friendship',
        params: <String, dynamic>{'p_other': friendUserId},
      );
    } catch (e) {
      // Removal must succeed locally even if the backend is unreachable; the
      // friend is blocked on this device either way, and the row is removed on
      // the next successful attempt.
      _noteFailure(e);
    }
  }

  /// New friendships that are already confirmed (e.g. the peer confirmed while
  /// this device was offline) so the local friend list can be reconciled.
  @override
  Future<List<RemotePeer>> confirmedFriends() async {
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('friendships')
          .select('id, requester_id, addressee_id, status')
          .eq('status', 'confirmed');
      final List<RemotePeer> peers = <RemotePeer>[];
      for (final Map<String, dynamic> row in rows) {
        final Object? requester = row['requester_id'];
        final Object? addressee = row['addressee_id'];
        final String? other = (requester == _uid ? addressee : requester)
            ?.toString();
        if (other == null) continue;
        final RemotePeer? peer = await _fetchPeer(other);
        if (peer != null) peers.add(peer);
      }
      return peers;
    } catch (e) {
      _noteFailure(e);
      return const <RemotePeer>[];
    }
  }

  Future<RemotePeer?> _fetchPeer(String uid) async {
    try {
      final Object? row = await client
          .from('profiles')
          .select('id, display_name, role')
          .eq('id', uid)
          .maybeSingle();
      if (row is Map<String, dynamic>) return _peerFromRow(row);
    } catch (e) {
      _noteFailure(e);
    }
    return null;
  }

  // ---------------- Messages ----------------

  @override
  Future<bool> sendMessage(
    ChatMessage message, {
    required String toRemoteUserId,
  }) async {
    final String? uid = _uid;
    if (uid == null) return false;
    try {
      // The client-generated id is the primary key, so a retry after a lost
      // response cannot duplicate the message: the insert is idempotent.
      await client.from('messages').upsert(
            <String, dynamic>{
              'id': message.id,
              'sender_id': uid,
              'sender_name': message.senderName,
              'receiver_id': toRemoteUserId,
              'original_text': message.originalText,
              'translated_text': message.translatedText,
              'direction': message.direction.name,
              'emotion': message.emotion?.storageName,
              'created_at': message.timestamp.toUtc().toIso8601String(),
              'transcription': message.transcription,
            },
            // Never overwrite a row that already exists (e.g. the receiver has
            // already marked it read): an upsert retry must stay idempotent.
            ignoreDuplicates: true,
          );
      return true;
    } catch (e) {
      // A row level security refusal means "we are not (yet) confirmed
      // friends" - a STATE the app handles (message stays queued, the friend
      // link flips to pending), not a backend outage. Re-throw it so the
      // caller can react precisely, instead of flipping the whole backend to
      // error and scheduling reconnects (the old behaviour that produced an
      // endless 42501 log stream).
      if (e is PostgrestException && e.code == '42501') {
        throw PolicyRefusalException(
          'Message rejected: the friendship is not confirmed yet.',
        );
      }
      _noteFailure(e);
      return false;
    }
  }

  @override
  Future<void> markConversationRead(String friendUserId) async {
    final String? uid = _uid;
    if (uid == null) return;
    try {
      await client
          .from('messages')
          .update(<String, dynamic>{
            'read_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('sender_id', friendUserId)
          .eq('receiver_id', uid)
          .isFilter('read_at', null);
    } catch (e) {
      _noteFailure(e);
    }
  }

  /// Recent history for one friend. Used after a reinstall or a fresh device
  /// so the conversation is not visually empty while offline copies sync in.
  Future<List<ChatMessage>> fetchConversation(
    String friendUserId, {
    int limit = 200,
  }) async {
    final String? uid = _uid;
    if (uid == null) return const <ChatMessage>[];
    try {
      final List<Map<String, dynamic>> rows = await client
          .from('messages')
          .select()
          .or('sender_id.eq.$uid,receiver_id.eq.$uid')
          .order('created_at', ascending: false)
          .limit(limit);
      final List<ChatMessage> messages = <ChatMessage>[];
      for (final Map<String, dynamic> row in rows) {
        final String sender = row['sender_id']?.toString() ?? '';
        final String receiver = row['receiver_id']?.toString() ?? '';
        // Keep only this pair (the server filter above is a coarse prefilter).
        if (!((sender == uid && receiver == friendUserId) ||
            (sender == friendUserId && receiver == uid))) {
          continue;
        }
        final ChatMessage? message = _messageFromRow(row);
        if (message != null) messages.add(message);
      }
      return messages;
    } catch (e) {
      _noteFailure(e);
      return const <ChatMessage>[];
    }
  }

  // ---------------- Payload mapping ----------------

  ChatMessage? _messageFromRow(Map<String, dynamic> row) {
    final Object? id = row['id'];
    final Object? sender = row['sender_id'];
    final Object? receiver = row['receiver_id'];
    if (id is! String || sender is! String || receiver is! String) return null;
    return ChatMessage(
      id: id,
      senderId: sender,
      senderName: row['sender_name']?.toString() ?? 'Friend',
      receiverId: receiver,
      originalText: row['original_text']?.toString() ?? '',
      translatedText: row['translated_text']?.toString() ?? '',
      direction: directionFromName(row['direction']?.toString()),
      timestamp: DateTime.tryParse(row['created_at']?.toString() ?? '')
              ?.toLocal() ??
          DateTime.now(),
      emotion: Emotion.fromName(row['emotion']?.toString()),
      status: MessageStatus.sent,
      readByReceiver: row['read_at'] != null,
      transcription: row['transcription']?.toString(),
    );
  }

  RemotePeer? _peerFromRow(Map<String, dynamic> row) {
    // The RPCs return the peer under a couple of different column names
    // depending on which function produced the row.
    final Object? id = row['peer_id'] ?? row['id'] ?? row['user_id'];
    if (id is! String || id.isEmpty) return null;
    return RemotePeer(
      userId: id,
      displayName: row['display_name']?.toString() ?? 'Friend',
      role: roleFromName(row['role']?.toString()),
    );
  }

  /// Runs an RPC that returns a set of rows. A set-returning function comes
  /// back as a List; a scalar/tuple function comes back as a Map.
  Future<List<Map<String, dynamic>>> _rpcRows(
    String function,
    Map<String, dynamic> params,
  ) async {
    final dynamic result = await client.rpc<dynamic>(function, params: params);
    if (result is List) {
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map((Map<dynamic, dynamic> row) =>
              row.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)))
          .toList();
    }
    if (result is Map) {
      return <Map<String, dynamic>>[
        result.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)),
      ];
    }
    return const <Map<String, dynamic>>[];
  }

  // ---------------- State helpers ----------------

  void _setState(BackendState next) {
    if (_state == next) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// Records a recoverable failure and schedules a reconnect. The local app is
  /// unaffected: messages stay queued in the outbox.
  void _noteFailure(Object error) {
    _lastError = '$error';
    if (_state == BackendState.ready || _state == BackendState.connecting) {
      _setState(BackendState.error);
      _scheduleReconnect();
    }
  }

  void _fail(String message) {
    _lastError = message;
    _setState(BackendState.error);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _reconnect != null) return;
    // Fixed 20s cadence: simple, predictable and kind to battery. The app is
    // fully usable offline meanwhile, so a fast backoff curve buys nothing.
    _reconnect = Timer(const Duration(seconds: 20), () {
      _reconnect = null;
      if (_disposed) return;
      unawaited(initialize());
    });
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    await _messagesChannel?.unsubscribe();
    await _friendshipsChannel?.unsubscribe();
    await _profilesChannel?.unsubscribe();
    await _states.close();
    await _incoming.close();
    await _online.close();
    await _requests.close();
    await _friendshipUpdates.close();
  }
}
