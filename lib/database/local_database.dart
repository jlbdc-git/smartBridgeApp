import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/user_profile.dart';

/// Offline-first local storage for the whole messaging app.
///
/// Everything lives on the device (SharedPreferences JSON):
///  - the user's own profile
///  - confirmed friends
///  - full conversation history per friend
///  - a "removed friends" list so stale invite codes cannot be re-added
///
/// None of this requires an internet connection.
class LocalDatabase {
  LocalDatabase(this._prefs);

  final SharedPreferences _prefs;

  // ---- Keys ----
  static const String _kProfile = 'sb_profile';
  static const String _kFriends = 'sb_friends';
  static const String _kRemoved = 'sb_removed_friends';
  static const String _kMessagesPrefix = 'sb_msgs_'; // + friendId

  // ---------------- Profile ----------------

  Future<void> saveProfile(UserProfile profile) =>
      _prefs.setString(_kProfile, UserProfile.encode(profile));

  UserProfile? loadProfile() =>
      UserProfile.tryDecode(_prefs.getString(_kProfile));

  // ---------------- Friends ----------------

  List<Friend> loadFriends() => Friend.decodeList(_prefs.getString(_kFriends));

  Future<void> saveFriends(List<Friend> friends) =>
      _prefs.setString(_kFriends, Friend.encodeList(friends));

  Future<void> addFriend(Friend friend) async {
    final String? remoteId = friend.remoteId;
    final List<Friend> friends = loadFriends()
        // Never keep two local entries for the same backend user: reconnect
        // via a typed code after connecting by QR previously would otherwise
        // split the conversation in two.
        .where((Friend f) =>
            f.id != friend.id &&
            !(remoteId != null && f.remoteId == remoteId))
        .toList();
    friends.add(friend);
    await saveFriends(friends);
  }

  Future<void> removeFriend(String friendId) async {
    await saveFriends(
      loadFriends().where((Friend f) => f.id != friendId).toList(),
    );
    // Remember the removal so an old invite code cannot re-add this friend.
    final Set<String> removed = loadRemovedFriendIds()..add(friendId);
    await _prefs.setStringList(_kRemoved, removed.toList());
    await clearMessages(friendId);
  }

  Set<String> loadRemovedFriendIds() =>
      (_prefs.getStringList(_kRemoved) ?? <String>[]).toSet();

  Friend? findFriend(String id) {
    for (final Friend f in loadFriends()) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Finds the friend that owns a given backend user id. Needed because
  /// messages arriving over the internet are addressed with the sender's
  /// backend id, which is not the local friend id.
  Friend? findFriendByRemoteId(String remoteId) {
    if (remoteId.isEmpty) return null;
    for (final Friend f in loadFriends()) {
      if (f.remoteId == remoteId) return f;
    }
    return null;
  }

  // ---------------- Messages ----------------

  List<ChatMessage> loadMessages(String friendId) {
    final String? raw = _prefs.getString('$_kMessagesPrefix$friendId');
    if (raw == null || raw.isEmpty) return <ChatMessage>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        final List<ChatMessage> messages = decoded
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList();
        messages.sort(
          (ChatMessage a, ChatMessage b) => a.timestamp.compareTo(b.timestamp),
        );
        return messages;
      }
    } catch (_) {
      // Corrupted history falls back to an empty conversation.
    }
    return <ChatMessage>[];
  }

  Future<void> saveMessages(String friendId, List<ChatMessage> messages) {
    final List<ChatMessage> sorted = List<ChatMessage>.from(messages)
      ..sort(
        (ChatMessage a, ChatMessage b) => a.timestamp.compareTo(b.timestamp),
      );
    return _prefs.setString(
      '$_kMessagesPrefix$friendId',
      jsonEncode(sorted.map((ChatMessage m) => m.toJson()).toList()),
    );
  }

  /// Inserts or updates a message in the conversation with [friendId].
  Future<void> upsertMessage(String friendId, ChatMessage message) async {
    final List<ChatMessage> messages = loadMessages(friendId)
        .where((ChatMessage m) => m.id != message.id)
        .toList();
    messages.add(message);
    await saveMessages(friendId, messages);
  }

  Future<void> clearMessages(String friendId) =>
      _prefs.remove('$_kMessagesPrefix$friendId');

  /// Privacy setting: wipe every stored conversation.
  Future<void> deleteAllConversations() async {
    final List<String> keys = _prefs
        .getKeys()
        .where((String k) => k.startsWith(_kMessagesPrefix))
        .toList();
    for (final String key in keys) {
      await _prefs.remove(key);
    }
  }
}
