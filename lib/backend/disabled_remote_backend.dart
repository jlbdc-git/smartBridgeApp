import 'dart:async';

import '../models/chat_message.dart';
import '../models/user_profile.dart';
import 'remote_backend.dart';

/// The backend used when this build has no Supabase credentials, or when the
/// configured credentials were rejected (see [BackendConfig.problem]).
///
/// It is deliberately, aggressively inert:
///  * every stream is empty and never closes,
///  * every operation reports failure instead of pretending to succeed,
///  * nothing touches the network.
///
/// This is what guarantees the rule "the application must not require the
/// backend yet": the offline + LAN experience is bit-for-bit the same with or
/// without credentials compiled in.
class DisabledRemoteBackend implements RemoteBackend {
  DisabledRemoteBackend({this.reason = 'Not configured'});

  /// Why the backend is off, surfaced in Settings for transparency.
  final String reason;

  final StreamController<BackendState> _states =
      StreamController<BackendState>.broadcast();

  @override
  BackendState get state => BackendState.unconfigured;

  @override
  String? get userId => null;

  @override
  String? get lastError => null;

  @override
  Stream<BackendState> get stateChanges => _states.stream;

  @override
  Stream<ChatMessage> get incomingMessages =>
      const Stream<ChatMessage>.empty();

  @override
  Stream<String> get friendsOnline => const Stream<String>.empty();

  @override
  Stream<RemoteRequest> get incomingRequests =>
      const Stream<RemoteRequest>.empty();

  @override
  Stream<RemoteFriendship> get friendshipUpdates =>
      const Stream<RemoteFriendship>.empty();

  @override
  Future<void> initialize() async {
    // Intentionally does nothing: no credentials, no connection attempt.
  }

  @override
  Future<bool> publishProfile({
    required String displayName,
    required UserRole role,
    String? inviteCode,
  }) async =>
      false;

  @override
  Future<RemotePeer?> lookupInviteCode(String code) async => null;

  @override
  Future<RemoteRequestOutcome?> requestFriendship(String code) async => null;

  @override
  Future<bool> confirmFriendship(String friendshipId) async => false;

  @override
  Future<bool> declineFriendship(String friendshipId) async => false;

  @override
  Future<List<RemoteFriendship>> listMyRequests() async =>
      const <RemoteFriendship>[];

  @override
  Future<List<RemotePeer>> confirmedFriends() async => const <RemotePeer>[];

  @override
  Future<bool> sendMessage(
    ChatMessage message, {
    required String toRemoteUserId,
  }) async =>
      false;

  @override
  Future<void> markConversationRead(String friendUserId) async {}

  @override
  Future<void> revokeFriendship(String friendUserId) async {}

  @override
  Future<void> dispose() => _states.close();
}
