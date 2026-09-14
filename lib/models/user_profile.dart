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
  });

  /// Random persistent identifier for this device's user.
  /// Shared with friends ONLY inside confirmed friend connections / QR codes.
  final String id;
  final String name;
  final UserRole role;

  UserProfile copyWith({String? name, UserRole? role}) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      role: role ?? this.role,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      role: roleFromName(json['role'] as String?),
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
  });

  final String id;
  final String name;
  final UserRole role;
  final DateTime addedAt;

  Friend copyWith({String? name}) {
    return Friend(
      id: id,
      name: name ?? this.name,
      role: role,
      addedAt: addedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'role': role.name,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      role: roleFromName(json['role'] as String?),
      addedAt: DateTime.tryParse((json['addedAt'] ?? '') as String) ??
          DateTime.now(),
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
