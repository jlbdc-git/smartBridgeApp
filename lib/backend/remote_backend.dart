import '../models/chat_message.dart';
import '../models/user_profile.dart';

/// Lifecycle of the optional cloud backend.
enum BackendState {
  /// No SUPABASE_URL / SUPABASE_ANON_KEY in this build: the backend is inert
  /// and the app runs on the local + LAN paths only.
  unconfigured,

  /// Credentials are present; the client is signing in / subscribing.
  connecting,

  /// Signed in, realtime subscribed, ready to deliver messages.
  ready,

  /// Configured but unusable right now (offline, bad key, backend down).
  /// The app keeps working locally and retries later.
  error,
}

/// Another person, as identified by an exact invite-code lookup.
///
/// Only ever produced from a code the user physically obtained (scanned or
/// typed). There is no listing/search API, by design.
class RemotePeer {
  const RemotePeer({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  /// The peer's backend user id (Supabase `auth.uid()`).
  final String userId;
  final String displayName;
  final UserRole role;
}

/// An inbound "someone scanned my code" request that needs my confirmation.
class RemoteRequest {
  const RemoteRequest({
    required this.friendshipId,
    required this.peer,
  });

  /// Row id of the pending friendship, used to confirm it.
  final String friendshipId;
  final RemotePeer peer;
}

/// The cloud backend contract.
///
/// IMPLEMENTATIONS
///  * [DisabledRemoteBackend] - used when no credentials are configured.
///  * `SupabaseRemoteBackend`   - the real client.
///
/// Keeping this an interface means the chat pipeline, the outbox and the
/// transports can all be exercised in unit tests without any network, and that
/// the app cannot accidentally depend on the backend existing.
abstract interface class RemoteBackend {
  /// Current lifecycle state.
  BackendState get state;

  /// My backend user id once signed in, otherwise null.
  String? get userId;

  /// Last error message, for the Settings status row. Null when healthy.
  String? get lastError;

  /// State transitions, so the UI can show "connecting..." honestly.
  Stream<BackendState> get stateChanges;

  /// Messages addressed to me that arrived while the app was running.
  Stream<ChatMessage> get incomingMessages;

  /// Backend user ids of confirmed friends currently connected to realtime.
  /// Used to flush the local outbox the moment a friend becomes reachable.
  Stream<String> get friendsOnline;

  /// Inbound connection requests waiting for MY confirmation.
  Stream<RemoteRequest> get incomingRequests;

  /// Connects, signs in and subscribes. Never throws: failures move [state]
  /// to [BackendState.error]. A no-op when unconfigured.
  Future<void> initialize();

  /// Publishes/refreshes my own profile row, including the current invite
  /// code. Returns false when the backend is not usable.
  Future<bool> publishProfile({
    required String displayName,
    required UserRole role,
    String? inviteCode,
  });

  /// Exact-match invite-code lookup. Returns null when the code is unknown,
  /// expired or the backend is unavailable.
  Future<RemotePeer?> lookupInviteCode(String code);

  /// Creates a pending friendship with the owner of [code]. The other side
  /// still has to confirm before any message can be sent.
  Future<RemotePeer?> requestFriendship(String code);

  /// Accepts a pending friendship (the code owner's side).
  Future<bool> confirmFriendship(String friendshipId);

  /// Uploads one message to [toRemoteUserId] (a backend user id, which is not
  /// necessarily the local friend id). Returns false when it could not be
  /// stored, so the caller keeps it in the outbox and retries (offline-first).
  Future<bool> sendMessage(
    ChatMessage message, {
    required String toRemoteUserId,
  });

  /// Marks every message from [friendUserId] as read, so read status travels
  /// between devices.
  Future<void> markConversationRead(String friendUserId);

  /// Ends the friendship on the backend: the peer can no longer read or send
  /// anything. Message history already delivered stays where it is.
  Future<void> revokeFriendship(String friendUserId);

  /// Releases sockets/subscriptions.
  Future<void> dispose();
}
