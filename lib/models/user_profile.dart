import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Roles a user can pick during setup. The whole UI adapts to this.
enum UserRole { blind, deaf }

UserRole roleFromName(String? name) {
  return name == 'deaf' ? UserRole.deaf : UserRole.blind;
}

/// The local user's profile. Stored in SharedPreferences as JSON.
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.role,
    this.remoteId,
  });

  /// Random persistent identifier for this device's user.
  /// Shared with friends ONLY inside confirmed friend connections / QR codes.
  final String id;
  final String name;
  final UserRole role;

  /// Backend user id (Supabase `auth.uid()`), set only once the optional
  /// internet backend is configured and signed in. Kept separate from [id] so
  /// an existing install keeps its friend list and history when the backend
  /// is switched on later. Null means "local/LAN only".
  final String? remoteId;

  UserProfile copyWith({String? name, UserRole? role, String? remoteId}) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'remoteId': remoteId,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      role: roleFromName(json['role'] as String?),
      remoteId: json['remoteId'] as String?,
    );
  }

  static String encode(UserProfile profile) => jsonEncode(profile.toJson());

  static UserProfile? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return UserProfile.fromJson(decoded);
    } catch (_) {
      // Corrupted profile falls back to setup screen.
    }
    return null;
  }
}

/// A confirmed friend. Only confirmed friends can chat with each other.
@immutable
class Friend {
  const Friend({
    required this.id,
    required this.name,
    required this.role,
    required this.addedAt,
    this.isSample = false,
    this.remoteId,
  });

  final String id;
  final String name;
  final UserRole role;
  final DateTime addedAt;

  /// True only for the built-in TEST/SAMPLE friend. Always shown with a
  /// "SAMPLE" marker so it can never be mistaken for a real person.
  final bool isSample;

  /// The friend's backend user id, when they were connected while both devices
  /// had the optional internet backend configured. Null means this friend can
  /// only be reached over the LAN.
  final String? remoteId;

  Friend copyWith({String? name, String? remoteId}) {
    return Friend(
      id: id,
      name: name ?? this.name,
      role: role,
      addedAt: addedAt,
      isSample: isSample,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  /// True when this friend can be reached over the internet.
  bool get isReachableOnline => remoteId != null && remoteId!.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'addedAt': addedAt.toIso8601String(),
        'isSample': isSample,
        'remoteId': remoteId,
      };

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      role: roleFromName(json['role'] as String?),
      addedAt: DateTime.tryParse((json['addedAt'] ?? '') as String) ??
          DateTime.now(),
      // Friends stored by previous versions have no flag: default to false.
      isSample: (json['isSample'] ?? false) as bool,
      remoteId: json['remoteId'] as String?,
    );
  }

  static String encodeList(List<Friend> friends) =>
      jsonEncode(friends.map((Friend f) => f.toJson()).toList());

  static List<Friend> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const <Friend>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(Friend.fromJson)
            .toList();
      }
    } catch (_) {
      // Corrupted list falls back to an empty friend list.
    }
    return const <Friend>[];
  }
}
