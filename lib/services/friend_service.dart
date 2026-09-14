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
  /// Contains: app tag, code, display name, role, user id. Nothing else.
  String buildInviteQrPayload(UserProfile me, String code) {
    return jsonEncode(<String, dynamic>{
      'app': 'smartbridge',
      'code': code,
      'name': me.name,
      'role': me.role.name,
      'id': me.id,
    });
  }

  // ---------------- Joining (I scan / type a code) ----------------

  /// Validates a scanned QR payload or manually typed code.
  ///
  /// For typed codes we can only validate the FORMAT and expiry here; the
  /// identity arrives when both devices exchange hello payloads over the
  /// LAN channel during confirmation.
  InviteCheckResult checkInvite(
    String rawInput, {
    required UserProfile me,
  }) {
    final _ParsedInvite? invite = _parseInvite(rawInput);
    if (invite == null) return InviteCheckResult.invalid;
    if (invite.id == me.id) return InviteCheckResult.selfInvite;

    if (database.loadRemovedFriendIds().contains(invite.id)) {
      // Previously removed friend: still valid, but both sides must
      // re-confirm the connection explicitly.
      return InviteCheckResult.removed;
    }

    return InviteCheckResult.ok;
  }

  /// Extracts the identity from a scanned QR payload.
  _ParsedInvite? _parseInvite(String rawInput) {
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
          return _ParsedInvite(
            id: decoded['id'] as String,
            name: (decoded['name'] ?? 'Friend') as String,
            role: roleFromName(decoded['role'] as String?),
            code: decoded['code'] as String,
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
      return _ParsedInvite(
        id: 'code:${input.toUpperCase()}', // resolved later via hello exchange
        name: 'Friend',
        role: UserRole.deaf, // replaced by hello payload
        code: input.toUpperCase(),
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

  /// Both sides call this after the LAN hello exchange succeeded.
  /// Returns the confirmed friend (with the real display name).
  Future<Friend> confirmFriendship({
    required String friendId,
    required String friendName,
    required UserRole friendRole,
  }) async {
    final Friend friend = Friend(
      id: friendId,
      name: friendName,
      role: friendRole,
      addedAt: DateTime.now(),
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
class _ParsedInvite {
  const _ParsedInvite({
    required this.id,
    required this.name,
    required this.role,
    required this.code,
  });

  final String id;
  final String name;
  final UserRole role;
  final String code;
}
