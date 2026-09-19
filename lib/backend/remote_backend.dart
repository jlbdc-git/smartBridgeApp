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

/// Result of sending a friend request. [confirmed] is true when the server
/// reports the pair is ALREADY friends (e.g. both scanned each other, or the
/// re-add path) - otherwise the request is pending the other side's accept.
class RemoteRequestOutcome {
  const RemoteRequestOutcome({required this.peer, required this.confirmed});

  final RemotePeer peer;
  final bool confirmed;
}

/// One row of my request history, from `list_my_requests()`.
enum RemoteFriendshipStatus { pending, confirmed, declined }

RemoteFriendshipStatus? friendshipStatusFromName(String? name) {
  switch (name) {
    case 'pending':
      return RemoteFriendshipStatus.pending;
    case 'confirmed':
      return RemoteFriendshipStatus.confirmed;
    case 'declined':
      return RemoteFriendshipStatus.declined;
    default:
      return null;
  }
}

class RemoteFriendship {
  const RemoteFriendship({
    required this.friendshipId,
    required this.incoming,
    required this.status,
    required this.peer,
  });

  final String friendshipId;

  /// True when the OTHER person invited me (I can accept/decline).
  final bool incoming;
  final RemoteFriendshipStatus status;
  final RemotePeer peer;
}

/// The backend refused a write because row level security rejected it -
/// almost always "the friendship is not confirmed (yet)". This is a STATE
/// problem, not a connectivity problem: the message must stay queued and the
/// friend link must flip to pending, but the backend must NOT flip to error
/// or spam reconnects over it.
class PolicyRefusalException implements Exception {
  const PolicyRefusalException(this.message);
  final String message;
  @override
  String toString() => 'PolicyRefusalException: $message';
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

  /// Changes to requests I SENT: accepted or declined on the other device.
  /// Also emitted when the whole request list should be re-read.
  Stream<RemoteFriendship> get friendshipUpdates;

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

  /// Sends a friend request to the owner of [code]. Returns null when the
  /// code is unknown/expired or the backend is unavailable; otherwise the
  /// outcome says whether the pair is already confirmed or still pending the
  /// other side's acceptance.
  Future<RemoteRequestOutcome?> requestFriendship(String code);

  /// Accepts a pending request (only the invited side can).
  Future<bool> confirmFriendship(String friendshipId);

  /// Declines a pending request (only the invited side can). The requester
  /// may send a fresh request later.
  Future<bool> declineFriendship(String friendshipId);

  /// Every friendship row I am part of (pending/confirmed/declined, both
  /// directions). Powers the Friend Requests section and the startup
  /// reconciliation that keeps both devices consistent.
  Future<List<RemoteFriendship>> listMyRequests();

  /// Confirmed friends' public profiles, for reconciling the local friend
  /// list after a restart or a request accepted while the app was closed.
  Future<List<RemotePeer>> confirmedFriends();

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
