import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbridgeapp/database/local_database.dart';
import 'package:smartbridgeapp/models/chat_message.dart';
import 'package:smartbridgeapp/models/user_profile.dart';

/// Regression tests for the offline store. Every mutating call is a
/// read-modify-write over one JSON key; before writes were serialized, two
/// operations running at once silently dropped each other's data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = LocalDatabase(await SharedPreferences.getInstance());
  });

  ChatMessage message(String id, {required String friendId, required int seq}) {
    return ChatMessage(
      id: id,
      senderId: friendId,
      senderName: 'Friend',
      receiverId: 'me',
      originalText: id,
      translatedText: id,
      direction: MessageDirection.deafToBlind,
      timestamp: DateTime(2026, 1, 1).add(Duration(seconds: seq)),
    );
  }

  test('concurrent upserts never lose a message', () async {
    const int count = 50;

    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < count; i++)
        db.upsertMessage('friend-1', message('m-$i', friendId: 'friend-1', seq: i)),
    ]);

    final Set<String> ids =
        db.loadMessages('friend-1').map((ChatMessage m) => m.id).toSet();
    expect(ids.length, count, reason: 'every concurrent write must persist');
  });

  test('concurrent friend adds all persist and stay de-duplicated', () async {
    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < 20; i++)
        db.addFriend(
          Friend(
            id: 'f-$i',
            name: 'Friend $i',
            role: UserRole.deaf,
            addedAt: DateTime(2026, 1, 1),
          ),
        ),
    ]);

    expect(db.loadFriends().length, 20);
  });

  test('removeFriend also clears that conversation', () async {
    await db.addFriend(
      Friend(
        id: 'f-x',
        name: 'X',
        role: UserRole.blind,
        addedAt: DateTime(2026, 1, 1),
      ),
    );
    await db.upsertMessage('f-x', message('m-1', friendId: 'f-x', seq: 1));

    await db.removeFriend('f-x');

    expect(db.findFriend('f-x'), isNull);
    expect(db.loadMessages('f-x'), isEmpty);
    expect(db.loadRemovedFriendIds(), contains('f-x'));
  });
}
