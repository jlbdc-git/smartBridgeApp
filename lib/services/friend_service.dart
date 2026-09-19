import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/local_database.dart';
import '../models/user_profile.dart';

/// Result of checking an invite code entered manually or scanned from QR.
enum InviteCheckResult {
  ok,          // valid, can confirm
  expired,     // past its TTL
  removed,     // user removed this friend before - needs fresh confirmation
  selfInvite,  // scanned own code
  invalid,     // malformed / unknown code
}

/// Offline-first friend system.
///
/// PRIVACY RULES (from the spec):
///  * No public user search, no directory, no random friend requests.
///  * Users must meet physically and exchange a QR code or short code.
///  * Codes contain only display name + role + id - never contact details.
///  * Codes expire; removal blocks stale codes from re-adding silently.
class FriendService {
  FriendService({required this.database, required this.prefs});

  final LocalDatabase database;
  final SharedPreferences prefs;

  /// Called whenever a (new) invite code is issued, so the owner can push it
  /// into the LAN announce and start resolving typed-code connections.
  void Function(String code)? onInviteChanged;

  static const String _kInviteCode = 'sb_invite_code';
  static const String _kInviteIssuedAt = 'sb_invite_issued_at';
  static const String _kPendingConfirmation = 'sb_pending_confirmation';

  /// How long an invite code stays valid.
  static const Duration inviteTtl = Duration(minutes: 30);

  // ---------------- Inviting (I show my code) ----------------

  /// Returns the current invite code for this user, creating one if needed.
  /// The code is short (e.g. "SB-4821-93") so it can also be typed by hand
  /// as the fallback when QR scanning is not possible.
  String getOrCreateInviteCode(UserProfile me) {
    final String? existing = prefs.getString(_kInviteCode);
    final String? issuedRaw = prefs.getString(_kInviteIssuedAt);
    final DateTime? issuedAt =
        issuedRaw == null ? null : DateTime.tryParse(issuedRaw);

    final bool fresh = existing != null &&
        issuedAt != null &&
        DateTime.now().difference(issuedAt) < inviteTtl;
    if (fresh) {
      return existing;
    }

    final String code = _generateCode();
    prefs.setString(_kInviteCode, code);
    prefs.setString(_kInviteIssuedAt, DateTime.now().toIso8601String());
    onInviteChanged?.call(code);
    return code;
  }

  /// Seconds left before the current code expires (for the countdown UI).
  int inviteSecondsLeft() {
    final String? issuedRaw = prefs.getString(_kInviteIssuedAt);
    if (issuedRaw == null) return 0;
    final DateTime? issuedAt = DateTime.tryParse(issuedRaw);
    if (issuedAt == null) return 0;
    final int elapsed =
        DateTime.now().difference(issuedAt).inMilliseconds;
    final int ttl = inviteTtl.inMilliseconds;
    return elapsed >= ttl ? 0 : ((ttl - elapsed) / 1000).ceil();
  }

  /// QR payload: compact JSON with the minimum needed to connect.
  /// Contains: app tag, code, display name, role, user id, the issue time (so
  /// a saved/screenshotted code can be recognised as expired) and, ONLY when
  /// the optional internet backend is configured, the backend user id so the
  /// two devices can also reach each other from different networks.
  /// No contact details, no phone number, no email - nothing else.
  String buildInviteQrPayload(
    UserProfile me,
    String code, {
    DateTime? issuedAt,
  }) {
    return jsonEncode(<String, dynamic>{
      'app': 'smartbridge',
      'code': code,
      'name': me.name,
      'role': me.role.name,
      'id': me.id,
      // Absent (not empty) when there is no backend, so older builds and
      // LAN-only installs see exactly the payload they always did.
      if (me.remoteId != null && me.remoteId!.isNotEmpty) 'uid': me.remoteId,
      // Same clock as the on-screen countdown, so both agree.
      'iat': (issuedAt ?? DateTime.now()).toIso8601String(),
    });
  }

  /// When the code currently on screen was issued (drives the QR payload
  /// timestamp so the countdown and the payload cannot drift apart).
  DateTime? inviteIssuedAt() {
    final String? issuedRaw = prefs.getString(_kInviteIssuedAt);
    return issuedRaw == null ? null : DateTime.tryParse(issuedRaw);
  }

  /// The stored invite code, if any (used in LAN announces). It may be older
  /// than the TTL: announces use it only so a peer who connected with a typed
  /// code can match this device to the real user id. It never creates one.
  String? storedInviteCode() {
    final String? code = prefs.getString(_kInviteCode);
    return (code == null || code.isEmpty) ? null : code;
  }

  // ---------------- Joining (I scan / type a code) ----------------

  /// Validates a scanned QR payload or manually typed code.
  ///
  /// For typed codes only the FORMAT (and expiry, for a QR payload) can be
  /// checked locally. The identity is then resolved in one of two ways:
  ///  * internet backend configured -> server-side exact-code lookup;
  ///  * LAN only -> the peer's own announce packet, once both devices are on
  ///    the same network.
  InviteCheckResult checkInvite(
    String rawInput, {
    required UserProfile me,
  }) {
    final InviteIdentity? invite = parseInvite(rawInput);
    if (invite == null) return InviteCheckResult.invalid;
    if (invite.id == me.id) return InviteCheckResult.selfInvite;

    // A QR code carries its issue time, so a screenshotted code that is older
    // than the TTL is rejected instead of connecting to a stale identity.
    // (A hand-typed code has no timestamp, so only its format can be checked.)
    final DateTime? issuedAt = invite.issuedAt;
    if (issuedAt != null && DateTime.now().difference(issuedAt) > inviteTtl) {
      return InviteCheckResult.expired;
    }

    if (database.loadRemovedFriendIds().contains(invite.id)) {
      // Previously removed friend: still valid, but both sides must
      // re-confirm the connection explicitly.
      return InviteCheckResult.removed;
    }

    return InviteCheckResult.ok;
  }

  /// Parses a scanned QR payload or a hand-typed code into the identity it
  /// carries. Returns null when the input is not a SmartBridge code at all.
  ///
  /// Public so the Add Friend screen reuses exactly this logic instead of
  /// re-implementing JSON parsing (they drifted apart once already, which made
  /// typed-code connections silently never resolve).
  InviteIdentity? parseInvite(String rawInput) {
    final String input = rawInput.trim();
    if (input.isEmpty) return null;

    // QR payload (JSON)?
    if (input.startsWith('{')) {
      try {
        final Object? decoded = jsonDecode(input);
        if (decoded is Map<String, dynamic> &&
            decoded['app'] == 'smartbridge' &&
            decoded['id'] is String &&
            decoded['code'] is String) {
          final Object? uid = decoded['uid'];
          return InviteIdentity(
            id: decoded['id'] as String,
            name: (decoded['name'] ?? 'Friend') as String,
            role: roleFromName(decoded['role'] as String?),
            code: decoded['code'] as String,
            issuedAt: DateTime.tryParse((decoded['iat'] ?? '') as String),
            remoteId: uid is String && uid.isNotEmpty ? uid : null,
            fromQr: true,
          );
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    // Typed code - validate format SB-####-## (digits or letters).
    final RegExp codePattern = RegExp(r'^SB-[A-Z0-9]{3,8}-[A-Z0-9]{2,4}$');
    if (codePattern.hasMatch(input.toUpperCase())) {
      final String code = input.toUpperCase();
      return InviteIdentity(
        // A placeholder id; resolved to the real identity when the peer
        // announces itself on the local network, or immediately by the
        // backend when it is configured (see ChatService / AddFriendScreen).
        id: 'code:$code',
        name: 'Friend',
        role: UserRole.deaf, // replaced by the peer's real role
        code: code,
      );
    }
    return null;
  }

  // ---------------- Confirmation (both sides) ----------------

  /// Stores the other user's identity before mutual confirmation.
  Future<void> stagePendingConfirmation(Friend friend) =>
      prefs.setString(_kPendingConfirmation, jsonEncode(friend.toJson()));

  Friend? takePendingConfirmation() {
    final String? raw = prefs.getString(_kPendingConfirmation);
    if (raw == null) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Friend.fromJson(decoded);
      }
    } catch (_) {
      // Corrupt pending entry is dropped.
    }
    return null;
  }

  Future<void> clearPendingConfirmation() =>
      prefs.remove(_kPendingConfirmation);

  /// Both sides call this after the connection was confirmed (in person, or
  /// over the backend). Returns the confirmed friend (with the real display
  /// name).
  ///
  /// [remoteId] is the peer's backend user id when the connection was made by
  /// two backend-enabled builds; it is what makes internet delivery possible.
  ///
  /// [status] records how far the connection has progressed: [pending] means
  /// a request was sent (or received) but the other side has not accepted
  /// yet - the friend shows in the list but chatting stays blocked.
  Future<Friend> confirmFriendship({
    required String friendId,
    required String friendName,
    required UserRole friendRole,
    String? remoteId,
    ConnectionStatus status = ConnectionStatus.accepted,
  }) async {
    final Friend friend = Friend(
      id: friendId,
      name: friendName,
      role: friendRole,
      addedAt: DateTime.now(),
      remoteId: remoteId,
      connectionStatus: status,
    );
    await database.addFriend(friend);
    await clearPendingConfirmation();
    return friend;
  }

  Future<void> removeFriend(String friendId) => database.removeFriend(friendId);

  List<Friend> loadFriends() => database.loadFriends();

  String _generateCode() {
    final DateTime now = DateTime.now();
    int seed = now.millisecondsSinceEpoch;
    int nextRand() {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return seed;
    }

    String digits(int n) {
      String out = '';
      for (int i = 0; i < n; i++) {
        out += (nextRand() % 10).toString();
      }
      return out;
    }

    return 'SB-${digits(4)}-${digits(2)}';
  }
}

@immutable
class InviteIdentity {
  const InviteIdentity({
    required this.id,
    required this.name,
    required this.role,
    required this.code,
    this.issuedAt,
    this.remoteId,
    this.fromQr = false,
  });

  final String id;
  final String name;
  final UserRole role;
  final String code;

  /// Only present for QR payloads; null for hand-typed codes.
  final DateTime? issuedAt;

  /// The peer's backend user id, when their code was generated by a build with
  /// the internet backend configured. Null for LAN-only peers.
  final String? remoteId;

  /// True when this came from a scanned QR payload (which carries a full
  /// identity) rather than a hand-typed short code.
  final bool fromQr;
}
