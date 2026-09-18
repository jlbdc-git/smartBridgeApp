import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbridgeapp/backend/backend_config.dart';
import 'package:smartbridgeapp/backend/remote_backend.dart';
import 'package:smartbridgeapp/database/local_database.dart';
import 'package:smartbridgeapp/models/chat_message.dart';
import 'package:smartbridgeapp/models/emotion.dart';
import 'package:smartbridgeapp/models/user_profile.dart';
import 'package:smartbridgeapp/models/ui_preferences.dart';
import 'package:smartbridgeapp/services/chat_service.dart';
import 'package:smartbridgeapp/services/connectivity_service.dart';
import 'package:smartbridgeapp/services/friend_service.dart';
import 'package:smartbridgeapp/services/session_service.dart';
import 'package:smartbridgeapp/services/sample_friend.dart';
import 'package:smartbridgeapp/services/transport/composite_transport.dart';
import 'package:smartbridgeapp/services/transport/lan_transport.dart';
import 'package:smartbridgeapp/services/transport/remote_transport.dart';
import 'package:smartbridgeapp/services/tts_service.dart';

/// Builds a SessionService exactly the way main.dart does (LAN + optional
/// internet transport), so the tests exercise the real wiring.
SessionService buildTestSession({
  required SharedPreferences prefs,
  required LocalDatabase database,
  RemoteBackend? backend,
}) {
  final LanTransport lan = LanTransport();
  final RemoteTransport? remote = backend == null
      ? null
      : RemoteTransport(backend: backend, database: database);
  final CompositeChatTransport transport = CompositeChatTransport(
    <ChatTransport>[lan, ?remote],
  );
  final TtsService tts = TtsService();
  return SessionService(
    prefs: prefs,
    database: database,
    tts: tts,
    lanTransport: lan,
    transport: transport,
    remoteTransport: remote,
    backend: backend,
    backendConfig: const BackendConfig(url: '', anonKey: ''),
    chatService: ChatService(database: database, transport: transport, tts: tts),
    connectivity: ConnectivityService(),
  );
}

/// Records sendToFriend calls; events can be fed manually via handleTransportEvent.
class _FakeTransport implements ChatTransport {
  _FakeTransport(this.deliveredTo);

  final List<String> deliveredTo;

  /// Whether the peer is currently reachable (flip to simulate coming online).
  bool online = false;

  @override
  Stream<Map<String, dynamic>> get events =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  void updateIdentity(Map<String, dynamic> identity) {}

  @override
  Future<bool> sendToFriend(String friendId, Map<String, dynamic> payload) async {
    if (!online) return false;
    deliveredTo.add(friendId);
    return true;
  }
}

/// Offline-first storage, friend codes and the built-in sample friend.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    database = LocalDatabase(prefs);
  });

  ChatMessage message({
    required String id,
    required String senderId,
    required String receiverId,
    DateTime? at,
    Emotion? emotion,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      senderName: 'Tester',
      receiverId: receiverId,
      originalText: 'original',
      translatedText: 'translated',
      direction: MessageDirection.blindToDeaf,
      timestamp: at ?? DateTime.now(),
      emotion: emotion,
    );
  }

  group('LocalDatabase (offline-first storage)', () {
    test('profile, friends and conversations survive a reload', () async {
      await database.saveProfile(
        const UserProfile(id: 'me', name: 'Ana', role: UserRole.blind),
      );
      await database.addFriend(Friend(
        id: 'f1',
        name: 'Ben',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      ));

      // A fresh LocalDatabase over the same storage simulates a restart.
      final LocalDatabase reloaded = LocalDatabase(prefs);
      expect(reloaded.loadProfile()!.name, 'Ana');
      expect(reloaded.loadFriends().single.name, 'Ben');
    });

    test('messages are stored and returned in timestamp order', () async {
      await database.upsertMessage(
        'f1',
        message(
          id: 'b',
          senderId: 'f1',
          receiverId: 'me',
          at: DateTime(2026, 1, 2),
        ),
      );
      await database.upsertMessage(
        'f1',
        message(
          id: 'a',
          senderId: 'me',
          receiverId: 'f1',
          at: DateTime(2026, 1, 1),
        ),
      );

      final List<ChatMessage> loaded = database.loadMessages('f1');
      expect(loaded.map((ChatMessage m) => m.id), <String>['a', 'b']);
    });

    test('upsertMessage updates instead of duplicating', () async {
      final ChatMessage original = message(
        id: 'dup',
        senderId: 'me',
        receiverId: 'f1',
      );
      await database.upsertMessage('f1', original);
      await database.upsertMessage(
        'f1',
        original.copyWith(status: MessageStatus.sent),
      );

      final List<ChatMessage> loaded = database.loadMessages('f1');
      expect(loaded.length, 1);
      expect(loaded.single.status, MessageStatus.sent);
    });

    test('corrupted conversation data falls back to empty, never crashes',
        () async {
      await prefs.setString('sb_msgs_f1', 'not-json{');
      expect(database.loadMessages('f1'), isEmpty);
    });

    test('removing a friend deletes the conversation and blocks the id',
        () async {
      await database.addFriend(Friend(
        id: 'f1',
        name: 'Ben',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      ));
      await database.upsertMessage(
        'f1',
        message(id: 'm1', senderId: 'f1', receiverId: 'me'),
      );

      await database.removeFriend('f1');

      expect(database.findFriend('f1'), isNull);
      expect(database.loadMessages('f1'), isEmpty);
      expect(database.loadRemovedFriendIds(), contains('f1'));
    });

    test('deleting all conversations keeps friends (privacy setting)',
        () async {
      await database.addFriend(Friend(
        id: 'f1',
        name: 'Ben',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      ));
      await database.upsertMessage(
        'f1',
        message(id: 'm1', senderId: 'me', receiverId: 'f1'),
      );

      await database.deleteAllConversations();

      expect(database.loadMessages('f1'), isEmpty);
      expect(database.loadFriends(), hasLength(1));
    });
  });

  group('FriendService invite codes', () {
    const UserProfile me = UserProfile(
      id: 'me-id',
      name: 'Ana',
      role: UserRole.blind,
    );

    test('codes match the shareable format and stay stable until they expire',
        () {
      final FriendService service =
          FriendService(database: database, prefs: prefs);

      final String first = service.getOrCreateInviteCode(me);
      expect(RegExp(r'^SB-\d{4}-\d{2}$').hasMatch(first), isTrue);
      expect(service.getOrCreateInviteCode(me), first);
      expect(service.inviteSecondsLeft(), greaterThan(0));
    });

    test('QR payload carries no personal data beyond name, role and id', () {
      final FriendService service =
          FriendService(database: database, prefs: prefs);
      final String payload = service.buildInviteQrPayload(me, 'SB-1234-56');
      final Map<String, dynamic> decoded =
          jsonDecode(payload) as Map<String, dynamic>;

      expect(
        decoded.keys.toSet(),
        <String>{'app', 'code', 'name', 'role', 'id', 'iat'},
      );
      expect(decoded.containsKey('phone'), isFalse);
      expect(decoded.containsKey('email'), isFalse);
    });

    test('a fresh QR payload is accepted', () {
      final FriendService service =
          FriendService(database: database, prefs: prefs);
      final Friend other = Friend(
        id: 'other-id',
        name: 'Ben',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      );
      final String payload = service.buildInviteQrPayload(
        UserProfile(id: other.id, name: other.name, role: other.role),
        'SB-1234-56',
      );

      expect(
        service.checkInvite(payload, me: me),
        InviteCheckResult.ok,
      );
    });

    test('ACCEPTANCE D: an expired QR code is rejected', () {
      final FriendService service =
          FriendService(database: database, prefs: prefs);
      // A code photographed 31 minutes ago and presented now.
      final String stale = jsonEncode(<String, dynamic>{
        'app': 'smartbridge',
        'code': 'SB-1234-56',
        'name': 'Ben',
        'role': 'deaf',
        'id': 'other-id',
        'iat': DateTime.now()
            .subtract(const Duration(minutes: 31))
            .toIso8601String(),
      });

      expect(service.checkInvite(stale, me: me), InviteCheckResult.expired);
    });

    test('garbage and self codes are rejected', () {
      final FriendService service =
          FriendService(database: database, prefs: prefs);
      expect(service.checkInvite('hello world', me: me),
          InviteCheckResult.invalid);
      expect(service.checkInvite('', me: me), InviteCheckResult.invalid);

      final String mine = service.buildInviteQrPayload(me, 'SB-1234-56');
      expect(service.checkInvite(mine, me: me), InviteCheckResult.selfInvite);
    });

    test('a removed friend must re-confirm before chatting again', () async {
      final FriendService service =
          FriendService(database: database, prefs: prefs);
      await database.removeFriend('other-id');
      final String payload = service.buildInviteQrPayload(
        const UserProfile(id: 'other-id', name: 'Ben', role: UserRole.deaf),
        'SB-1234-56',
      );

      expect(service.checkInvite(payload, me: me), InviteCheckResult.removed);
    });
  });  group('LAN connectivity (pending flush + typed-code resolution)', () {
    late ChatService alice;

    /// Captures deliveries instead of opening real sockets.
    late _FakeTransport fake;

    setUp(() {
      fake = _FakeTransport(<String>[]);
      alice = ChatService(
        database: database,
        transport: fake,
        tts: TtsService(),
      );
      alice.setMe(const UserProfile(
        id: 'alice',
        name: 'Alice',
        role: UserRole.blind,
      ));
    });

    tearDown(() => alice.dispose());

    test('an announce event flushes the pending outbox for that friend',
        () async {
      final Friend friend = Friend(
        id: 'bob',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      );
      await database.addFriend(friend);

      // Delivery fails (no address known yet): stored as pending.
      final ChatMessage pending = await alice.sendMessage(
        friend: friend,
        originalText: 'hi',
        translatedText: 'hi',
        direction: MessageDirection.blindToDeaf,
      );
      expect(pending.status, MessageStatus.sending);

      // The friend comes online and announces itself.
      fake.online = true;
      await alice.handleTransportEvent(<String, dynamic>{
        'type': 'announce',
        'id': 'bob',
        'name': 'Bob',
        'role': 'deaf',
      });

      final List<ChatMessage> after = database.loadMessages('bob');
      expect(
        after.where((ChatMessage m) => m.id == pending.id).single.status,
        MessageStatus.sent,
        reason: 'the outbox should flush when the friend announces',
      );
      expect(fake.deliveredTo, contains('bob'));
    });

    test('a typed-code placeholder resolves to the announced identity',
        () async {
      const String placeholder = 'code:SB-1234-56';
      await database.addFriend(Friend(
        id: placeholder,
        name: 'Friend (SB-1234-56)',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      ));
      await database.upsertMessage(
        placeholder,
        ChatMessage(
          id: 'queued',
          senderId: 'alice',
          senderName: 'Alice',
          receiverId: placeholder,
          originalText: 'hi',
          translatedText: 'hi',
          direction: MessageDirection.blindToDeaf,
          timestamp: DateTime.now(),
          status: MessageStatus.sending,
        ),
      );

      // The real peer announces itself carrying the same invite code.
      await alice.handleTransportEvent(<String, dynamic>{
        'type': 'announce',
        'id': 'real-bob-id',
        'name': 'Bob Real',
        'role': 'deaf',
        'code': 'SB-1234-56',
      });

      expect(database.findFriend(placeholder), isNull,
          reason: 'the placeholder must be replaced');
      final Friend? resolved = database.findFriend('real-bob-id');
      expect(resolved, isNotNull);
      expect(resolved!.name, 'Bob Real');
      expect(resolved.role, UserRole.deaf);
      // Queued messages were carried across to the real conversation key.
      expect(
        database.loadMessages('real-bob-id').map((ChatMessage m) => m.id),
        contains('queued'),
      );
      expect(database.loadMessages(placeholder), isEmpty);
    });

    test('announces carry the invite code for typed-code resolution', () {
      alice.inviteCodeProvider = () => 'SB-9999-99';
      final Map<String, dynamic> identity = alice.currentIdentity();
      expect(identity['code'], 'SB-9999-99');
      expect(identity['id'], 'alice');
    });
  });

  group('SessionService settings sync', () {
    late SessionService session;

    setUp(() {
      session = buildTestSession(prefs: prefs, database: database);
    });

    test('a preference change is visible in memory and on disk at once',
        () async {
      final Future<void> applying = session.updateUiPreferences(
        const AppUiPreferences()
            .copyWith(textScale: 1.3, ttsRate: 0.9, highContrast: true),
      );

      // Synchronous update: screens reading session.ui rebuild with the new
      // value on the very next frame.
      expect(session.ui.textScale, 1.3);
      expect(session.ui.ttsRate, 0.9);

      await applying;

      // ...and it is stored for the next launch.
      expect(prefs.getDouble('pref_text_scale'), 1.3);
      expect(prefs.getDouble('pref_tts_rate'), 0.9);
      expect(prefs.getBool('pref_high_contrast'), isTrue);
    });

    test('a brand-new account can send immediately after setup', () async {
      // Regression: completeSetup() used to leave the chat layer without an
      // identity, so the first message of a fresh install threw.
      await session.completeSetup(name: 'Bea', role: UserRole.deaf);
      final Friend friend = await session.addSampleFriend();

      final ChatMessage sent = await session.chatService.sendMessage(
        friend: friend,
        originalText: 'hi',
        translatedText: 'hi',
        direction: MessageDirection.deafToBlind,
      );

      expect(sent.senderId, session.profile!.id);
      expect(sent.status, MessageStatus.sent);
    });

    test('renaming keeps the chat identity in sync', () async {
      await session.completeSetup(name: 'Bea', role: UserRole.deaf);
      await session.updateProfile(name: 'Bea B');

      expect(session.chatService.me!.name, 'Bea B');
    });

    test('turning text-to-speech off silences the voice engine', () async {
      await session.setTtsEnabled(false);

      expect(session.ttsEnabled, isFalse);
      expect(session.tts.enabled, isFalse);
      expect(prefs.getBool('sb_tts_enabled'), isFalse);
    });

    test('TTS, visual notifications and vibration are independent switches',
        () async {
      await session.setTtsEnabled(false);

      // Silencing the voice must not disable visual alerts or vibration.
      expect(session.notificationsEnabled, isTrue);
      expect(session.vibrationEnabled, isTrue);
    });

    test('the Accessibility haptics switch really silences vibration',
        () async {
      // Regression: "Haptics" was stored and then never consulted by the
      // messaging app, so it was a switch that changed nothing.
      expect(session.shouldVibrateOnIncoming, isTrue);

      await session.updateUiPreferences(
        session.ui.copyWith(hapticsEnabled: false),
      );
      expect(session.shouldVibrateOnIncoming, isFalse);
    });

    test('the Alerts vibration switch is honoured independently', () async {
      await session.setVibrationEnabled(false);
      expect(session.shouldVibrateOnIncoming, isFalse);

      await session.setVibrationEnabled(true);
      expect(session.shouldVibrateOnIncoming, isTrue);
    });

    test('a build with no backend reports that honestly', () {
      expect(session.internetMessagingAvailable, isFalse);
      expect(session.backendStatusLabel, contains('SUPABASE_URL'));
    });

    test('removing a friend is blocked from re-adding via their old code',
        () async {
      await session.completeSetup(name: 'Ana', role: UserRole.blind);
      final Friend friend = Friend(
        id: 'bob-1',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      );
      await database.addFriend(friend);
      await session.removeFriend(friend);

      expect(database.findFriend('bob-1'), isNull);
      expect(database.loadRemovedFriendIds(), contains('bob-1'));
    });
  });

  group('SampleFriendService', () {
    test('installs a clearly labelled TEST contact playing the other role',
        () async {
      final SampleFriendService service = SampleFriendService(
        database: database,
        onLocalMessage: (_) async {},
      );
      const UserProfile blindUser = UserProfile(
        id: 'me',
        name: 'Ana',
        role: UserRole.blind,
      );

      final Friend friend = await service.ensureInstalled(blindUser);

      expect(friend.id, SampleFriendService.friendId);
      expect(friend.isSample, isTrue);
      expect(friend.name.toLowerCase(), contains('sample'));
      // A blind tester needs a deaf partner to exercise the deaf pipeline.
      expect(friend.role, UserRole.deaf);
      expect(service.isInstalled, isTrue);
    });

    test('the sample flag survives a restart', () async {
      final SampleFriendService service = SampleFriendService(
        database: database,
        onLocalMessage: (_) async {},
      );
      await service.ensureInstalled(
        const UserProfile(id: 'me', name: 'Ana', role: UserRole.deaf),
      );

      expect(LocalDatabase(prefs).findFriend(SampleFriendService.friendId)!.isSample,
          isTrue);
    });
  });

  group('ChatService with the sample friend', () {
    late ChatService chat;

    setUp(() {
      chat = ChatService(
        database: database,
        transport: LanTransport(),
        tts: TtsService(),
      );
      chat.setMe(const UserProfile(
        id: 'me',
        name: 'Ana',
        role: UserRole.blind,
      ));
    });

    tearDown(() => chat.dispose());

    test('sending to the sample friend is marked delivered and answered',
        () async {
      final Friend friend =
          await chat.sampleFriend.ensureInstalled(chat.me!);

      final ChatMessage sent = await chat.sendMessage(
        friend: friend,
        originalText: 'You free tomorrow? I want go mall with you.',
        translatedText: 'You free tomorrow?',
        direction: MessageDirection.blindToDeaf,
      );
      // Local delivery: no network involved, so it is not left pending.
      expect(sent.status, MessageStatus.sent);

      final Future<ChatMessage> reply =
          chat.incomingMessages.firstWhere((ChatMessage m) => m.id != sent.id);

      final ChatMessage answer = await reply.timeout(
        const Duration(seconds: 5),
      );
      expect(answer.senderId, SampleFriendService.friendId);
      expect(answer.displayText.trim(), isNotEmpty);
      // The blind tester's partner is deaf, so the reply carries an emotion
      // that TTS announces before the text.
      expect(answer.emotion, isNotNull);
      expect(answer.readByReceiver, isFalse);
    });

    test('the sample friend is never placed on the LAN transport', () async {
      final Friend friend =
          await chat.sampleFriend.ensureInstalled(chat.me!);
      // No announce/address was ever registered for it: delivery is local.
      expect(chat.sampleFriend.isSampleFriend(friend.id), isTrue);

      final ChatMessage sent = await chat.sendMessage(
        friend: friend,
        originalText: 'hello',
        translatedText: 'hello',
        direction: MessageDirection.blindToDeaf,
      );
      expect(sent.status, MessageStatus.sent);
    });

    test('a deaf tester receives an emotion-free simple reply', () async {
      chat.setMe(const UserProfile(
        id: 'me',
        name: 'Bea',
        role: UserRole.deaf,
      ));
      final Friend friend =
          await chat.sampleFriend.ensureInstalled(chat.me!);
      expect(friend.role, UserRole.blind);

      final ChatMessage sent = await chat.sendMessage(
        friend: friend,
        originalText: 'i go mall tomorrow you want come?',
        translatedText: "I'm going to the mall tomorrow. "
            'Would you like to come with me?',
        direction: MessageDirection.deafToBlind,
        emotion: Emotion.happy,
      );

      final ChatMessage answer = await chat.incomingMessages
          .firstWhere((ChatMessage m) => m.id != sent.id)
          .timeout(const Duration(seconds: 5));

      // The blind partner has no emotion system: nothing is invented.
      expect(answer.emotion, isNull);
      expect(answer.direction, MessageDirection.blindToDeaf);
    });
  });
}
