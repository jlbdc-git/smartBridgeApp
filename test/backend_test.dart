import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbridgeapp/backend/backend_config.dart';
import 'package:smartbridgeapp/backend/disabled_remote_backend.dart';
import 'package:smartbridgeapp/backend/remote_backend.dart';
import 'package:smartbridgeapp/database/local_database.dart';
import 'package:smartbridgeapp/models/chat_message.dart';
import 'package:smartbridgeapp/models/emotion.dart';
import 'package:smartbridgeapp/models/user_profile.dart';
import 'package:smartbridgeapp/services/chat_service.dart';
import 'package:smartbridgeapp/services/transport/composite_transport.dart';
import 'package:smartbridgeapp/services/transport/lan_transport.dart';
import 'package:smartbridgeapp/services/transport/remote_transport.dart';
import 'package:smartbridgeapp/services/tts_service.dart';

/// A hand-written test double for the backend: no network, full control.
class _FakeBackend implements RemoteBackend {
  _FakeBackend({this.uid = 'backend-me'});

  final String uid;

  BackendState _state = BackendState.connecting;

  /// When false, message uploads report failure (simulates being offline).
  bool acceptSends = true;

  /// Every sendMessage call, as (messageId, receiverBackendId).
  final List<(String, String)> sent = <(String, String)>[];

  final List<String> revoked = <String>[];
  final List<String> readSynced = <String>[];

  /// Profiles published through publishProfile.
  final List<Map<String, dynamic>> publishedProfiles = <Map<String, dynamic>>[];

  final StreamController<BackendState> _states =
      StreamController<BackendState>.broadcast();
  final StreamController<ChatMessage> _incoming =
      StreamController<ChatMessage>.broadcast();
  final StreamController<String> _online = StreamController<String>.broadcast();
  final StreamController<RemoteRequest> _requests =
      StreamController<RemoteRequest>.broadcast();

  /// Test hooks: push events as if they came from the server.
  void emitIncoming(ChatMessage message) => _incoming.add(message);
  void emitOnline(String remoteUserId) => _online.add(remoteUserId);
  void emitRequest(RemoteRequest request) => _requests.add(request);

  /// Simulates the backend recovering after a failure.
  void recover() {
    _state = BackendState.ready;
    _states.add(_state);
  }

  @override
  BackendState get state => _state;

  @override
  String? get userId => _state == BackendState.ready ? uid : null;

  @override
  String? get lastError => null;

  @override
  Stream<BackendState> get stateChanges => _states.stream;

  @override
  Stream<ChatMessage> get incomingMessages => _incoming.stream;

  @override
  Stream<String> get friendsOnline => _online.stream;

  @override
  Stream<RemoteRequest> get incomingRequests => _requests.stream;

  @override
  Future<void> initialize() async {
    _state = BackendState.ready;
    _states.add(_state);
  }

  @override
  Future<bool> publishProfile({
    required String displayName,
    required UserRole role,
    String? inviteCode,
  }) async {
    publishedProfiles.add(<String, dynamic>{
      'displayName': displayName,
      'role': role.name,
      'inviteCode': inviteCode,
    });
    return true;
  }

  @override
  Future<RemotePeer?> lookupInviteCode(String code) async => null;

  @override
  Future<RemotePeer?> requestFriendship(String code) async => null;

  @override
  Future<bool> confirmFriendship(String friendshipId) async => true;

  @override
  Future<bool> sendMessage(
    ChatMessage message, {
    required String toRemoteUserId,
  }) async {
    if (!acceptSends) return false;
    sent.add((message.id, toRemoteUserId));
    return true;
  }

  @override
  Future<void> markConversationRead(String friendUserId) async {
    readSynced.add(friendUserId);
  }

  @override
  Future<void> revokeFriendship(String friendUserId) async {
    revoked.add(friendUserId);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _incoming.close();
    await _online.close();
    await _requests.close();
  }
}

/// A transport that always fails, standing in for "no LAN available".
class _DeadTransport implements ChatTransport {
  int sendAttempts = 0;
  StreamController<Map<String, dynamic>>? _controller;

  @override
  Stream<Map<String, dynamic>> get events =>
      (_controller ??= StreamController<Map<String, dynamic>>.broadcast()).stream;

  @override
  void updateIdentity(Map<String, dynamic> identity) {}

  @override
  Future<bool> sendToFriend(
    String friendId,
    Map<String, dynamic> payload,
  ) async {
    sendAttempts++;
    return false;
  }
}

/// A transport that always succeeds and records deliveries.
class _LiveTransport implements ChatTransport {
  _LiveTransport(this.name);

  final String name;
  final List<String> sentTo = <String>[];
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get events => _controller.stream;

  void emit(Map<String, dynamic> event) => _controller.add(event);

  @override
  void updateIdentity(Map<String, dynamic> identity) {}

  @override
  Future<bool> sendToFriend(
    String friendId,
    Map<String, dynamic> payload,
  ) async {
    sentTo.add(friendId);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late LocalDatabase database;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    database = LocalDatabase(prefs);
  });

  // ==========================================================================
  group('BackendConfig', () {
    test('an empty build is not configured and uses no network', () {
      const BackendConfig config = BackendConfig(url: '', anonKey: '');
      expect(config.isConfigured, isFalse);
      expect(config.problem, BackendConfigProblem.missingUrl);
      expect(config.problemMessage, contains('SUPABASE_URL'));
    });

    test('a URL without a key is not configured', () {
      const BackendConfig config =
          BackendConfig(url: 'https://demo.supabase.co', anonKey: '');
      expect(config.isConfigured, isFalse);
      expect(config.problem, BackendConfigProblem.missingKey);
    });

    test('plain http outside loopback is rejected (messages could be read)',
        () {
      const BackendConfig config = BackendConfig(
        url: 'http://demo.supabase.co',
        anonKey: 'sb_publishable_x',
      );
      expect(config.isConfigured, isFalse);
      expect(config.problem, BackendConfigProblem.insecureUrl);
    });

    test('http is tolerated only for a local Supabase instance', () {
      const BackendConfig config = BackendConfig(
        url: 'http://127.0.0.1:54321',
        anonKey: 'sb_publishable_x',
      );
      expect(config.isConfigured, isTrue);
    });

    test('a normal anon JWT is accepted', () {
      final BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: _jwt(<String, dynamic>{'role': 'anon', 'iss': 'supabase'}),
      );
      expect(config.isConfigured, isTrue);
      expect(config.problem, BackendConfigProblem.none);
    });

    test('a modern publishable key is accepted', () {
      const BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: 'sb_publishable_abc123',
      );
      expect(config.isConfigured, isTrue);
    });

    test('a service_role key is REFUSED: it would bypass every policy', () {
      final BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: _jwt(<String, dynamic>{'role': 'service_role'}),
      );
      expect(config.isConfigured, isFalse);
      expect(config.problem, BackendConfigProblem.privilegedKey);
    });

    test('a modern secret key is REFUSED', () {
      const BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: 'sb_secret_abc123',
      );
      expect(config.isConfigured, isFalse);
      expect(config.problem, BackendConfigProblem.privilegedKey);
    });

    test('the status message never leaks the key itself', () {
      final BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: _jwt(<String, dynamic>{'role': 'service_role'}),
      );
      expect(config.problemMessage, isNot(contains('service_role')));
      expect(config.problemMessage, isNot(contains(config.anonKey)));
      expect(config.problemMessage, isNot(contains('eyJ')));
    });

    test('a malformed token is not mistaken for a privileged one', () {
      const BackendConfig config = BackendConfig(
        url: 'https://demo.supabase.co',
        anonKey: 'not-a-jwt',
      );
      expect(BackendConfig.isPrivilegedKey('not-a-jwt'), isFalse);
      // Still configured: the server rejects a bad key, and refusing to boot
      // would be worse than a clear error in Settings.
      expect(config.isConfigured, isTrue);
    });

    test('decodeJwtPayload tolerates garbage', () {
      expect(BackendConfig.decodeJwtPayload(''), isNull);
      expect(BackendConfig.decodeJwtPayload('a.b'), isNull);
      expect(BackendConfig.decodeJwtPayload('a.b.c'), isNull);
    });
  });

  // ==========================================================================
  group('DisabledRemoteBackend', () {
    test('is inert: no identity, empty streams, no operation succeeds',
        () async {
      final DisabledRemoteBackend backend = DisabledRemoteBackend();

      expect(backend.state, BackendState.unconfigured);
      expect(backend.userId, isNull);
      await backend.initialize(); // must not throw

      expect(
        await backend.publishProfile(
          displayName: 'Ana',
          role: UserRole.blind,
          inviteCode: 'SB-1',
        ),
        isFalse,
      );
      expect(await backend.lookupInviteCode('SB-1'), isNull);
      expect(await backend.requestFriendship('SB-1'), isNull);
      expect(await backend.confirmFriendship('any'), isFalse);
      expect(
        await backend.sendMessage(
          _message(id: 'm1', from: 'a', to: 'b'),
          toRemoteUserId: 'b',
        ),
        isFalse,
      );

      // The streams are empty and completing them is safe.
      expect(await backend.incomingMessages.isEmpty, isTrue);
      expect(await backend.friendsOnline.isEmpty, isTrue);
      expect(await backend.incomingRequests.isEmpty, isTrue);
      await backend.dispose();
    });
  });

  // ==========================================================================
  group('CompositeChatTransport', () {
    test('falls through to the internet when the LAN cannot deliver', () async {
      final _DeadTransport lan = _DeadTransport();
      final _LiveTransport internet = _LiveTransport('internet');
      final CompositeChatTransport composite =
          CompositeChatTransport(<ChatTransport>[lan, internet]);

      final bool delivered = await composite.sendToFriend(
        'friend-1',
        <String, dynamic>{'type': 'chat'},
      );

      expect(delivered, isTrue);
      expect(lan.sendAttempts, 1);
      expect(internet.sentTo, <String>['friend-1']);
    });

    test('stops at the first success so same-Wi-Fi chat stays direct',
        () async {
      final _LiveTransport lan = _LiveTransport('lan');
      final _LiveTransport internet = _LiveTransport('internet');
      final CompositeChatTransport composite =
          CompositeChatTransport(<ChatTransport>[lan, internet]);

      await composite.sendToFriend('friend-1', <String, dynamic>{});

      expect(lan.sentTo, <String>['friend-1']);
      // No pointless mobile-data copy of a message already delivered locally.
      expect(internet.sentTo, isEmpty);
    });

    test('reports failure when no transport could deliver', () async {
      final CompositeChatTransport composite = CompositeChatTransport(
        <ChatTransport>[_DeadTransport(), _DeadTransport()],
      );
      expect(
        await composite.sendToFriend('friend-1', <String, dynamic>{}),
        isFalse,
      );
    });

    test('a throwing transport does not stop the others', () async {
      final _ThrowingTransport bad = _ThrowingTransport();
      final _LiveTransport good = _LiveTransport('good');
      final CompositeChatTransport composite =
          CompositeChatTransport(<ChatTransport>[bad, good]);

      expect(
        await composite.sendToFriend('friend-1', <String, dynamic>{}),
        isTrue,
      );
      expect(good.sentTo, <String>['friend-1']);
    });

    test('merges events from every transport', () async {
      final _LiveTransport lan = _LiveTransport('lan');
      final _LiveTransport internet = _LiveTransport('internet');
      final CompositeChatTransport composite =
          CompositeChatTransport(<ChatTransport>[lan, internet]);

      final List<Map<String, dynamic>> seen = <Map<String, dynamic>>[];
      final StreamSubscription<Map<String, dynamic>> sub =
          composite.events.listen(seen.add);

      lan.emit(<String, dynamic>{'type': 'chat', 'id': 'from-lan'});
      internet.emit(<String, dynamic>{'type': 'chat', 'id': 'from-internet'});
      await pumpEventQueue();

      expect(
        seen.map((Map<String, dynamic> e) => e['id']),
        containsAll(<String>['from-lan', 'from-internet']),
      );
      await sub.cancel();
      await composite.dispose();
    });
  });

  // ==========================================================================
  group('RemoteTransport', () {
    late _FakeBackend backend;
    late RemoteTransport transport;

    setUp(() async {
      backend = _FakeBackend(uid: 'backend-me');
      transport = RemoteTransport(backend: backend, database: database);
      await database.saveProfile(
        const UserProfile(
          id: 'local-me',
          name: 'Ana',
          role: UserRole.blind,
          remoteId: 'backend-me',
        ),
      );
      await transport.start(<String, dynamic>{
        'type': 'announce',
        'id': 'local-me',
        'name': 'Ana',
        'role': 'blind',
        'code': 'SB-1234-56',
      });
    });

    tearDown(() => backend.dispose());

    test('publishes my profile and invite code to the backend', () async {
      expect(backend.publishedProfiles, isNotEmpty);
      expect(backend.publishedProfiles.last['displayName'], 'Ana');
      expect(backend.publishedProfiles.last['inviteCode'], 'SB-1234-56');
    });

    test('re-publishes the profile when an offline backend recovers', () async {
      // A phone that started with no network never got its invite code onto
      // the server; the recovery edge is what fixes that.
      final int before = backend.publishedProfiles.length;

      backend.recover();
      await pumpEventQueue();

      expect(backend.publishedProfiles.length, greaterThan(before));
    });

    test('refuses to send to a friend with no backend identity', () async {
      final Friend lanOnly = Friend(
        id: 'lan-friend',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
      );
      await database.addFriend(lanOnly);

      final bool ok = await transport.sendToFriend(
        'lan-friend',
        _message(id: 'm1', from: 'local-me', to: 'lan-friend').toWire(),
      );

      expect(ok, isFalse);
      expect(backend.sent, isEmpty);
    });

    test('sends to a connected friend using their BACKEND id', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      final bool ok = await transport.sendToFriend(
        'bob-local',
        _message(id: 'm1', from: 'local-me', to: 'bob-local').toWire(),
      );

      expect(ok, isTrue);
      expect(backend.sent, <(String, String)>[('m1', 'backend-bob')]);
    });

    test('a failed upload keeps the message pending for a retry', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));
      backend.acceptSends = false;

      expect(
        await transport.sendToFriend(
          'bob-local',
          _message(id: 'm1', from: 'local-me', to: 'bob-local').toWire(),
        ),
        isFalse,
      );
    });

    test('an inbound cloud message is rewritten to LOCAL ids', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
      final StreamSubscription<Map<String, dynamic>> sub =
          transport.events.listen(events.add);

      backend.emitIncoming(_message(
        id: 'm-remote',
        from: 'backend-bob',
        to: 'backend-me',
      ));
      await pumpEventQueue();

      final Map<String, dynamic> chat = events
          .firstWhere((Map<String, dynamic> e) => e['type'] == 'chat');
      expect(chat['id'], 'm-remote');
      expect(chat['senderId'], 'bob-local', reason: 'must map to local id');
      expect(chat['receiverId'], 'local-me');
      await sub.cancel();
    });

    test('a message from an unknown backend id is dropped', () async {
      final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
      final StreamSubscription<Map<String, dynamic>> sub =
          transport.events.listen(events.add);

      backend.emitIncoming(
        _message(id: 'm-stranger', from: 'backend-stranger', to: 'backend-me'),
      );
      await pumpEventQueue();

      // Not a confirmed friend: nothing may reach the chat layer.
      expect(events, isEmpty);
      await sub.cancel();
    });

    test('a friend heartbeat announces them so the outbox can flush', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
      final StreamSubscription<Map<String, dynamic>> sub =
          transport.events.listen(events.add);

      backend.emitOnline('backend-bob');
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.first['type'], 'announce');
      expect(events.first['id'], 'bob-local');
      await sub.cancel();
    });

    test('read receipts and revocations use the backend id', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      await transport.markConversationRead('bob-local');
      await transport.revoke('bob-local');

      expect(backend.readSynced, <String>['backend-bob']);
      expect(backend.revoked, <String>['backend-bob']);
    });
  });

  // ==========================================================================
  group('ChatService: internet-addressed messages', () {
    late ChatService chat;

    setUp(() {
      chat = ChatService(
        database: database,
        transport: CompositeChatTransport(<ChatTransport>[_DeadTransport()]),
        tts: TtsService(),
      );
      chat.setMe(const UserProfile(
        id: 'local-me',
        name: 'Ana',
        role: UserRole.blind,
        remoteId: 'backend-me',
      ));
    });

    tearDown(() => chat.dispose());

    test('a message addressed with a backend id lands in the right thread',
        () async {
      // Bob was connected over the internet, so his local record carries his
      // backend id as well.
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      await chat.handleTransportEvent(<String, dynamic>{
        'type': 'chat',
        'id': 'm-remote',
        'senderId': 'backend-bob',
        'senderName': 'Bob',
        'receiverId': 'local-me',
        'originalText': 'hello',
        'translatedText': 'Hello.',
        'direction': 'deafToBlind',
        'timestamp': DateTime.now().toIso8601String(),
        'emotion': 'happy',
        'status': 'sent',
        'readByReceiver': false,
      });

      final List<ChatMessage> thread = database.loadMessages('bob-local');
      expect(thread, hasLength(1));
      expect(thread.first.senderId, 'bob-local',
          reason: 'normalised onto the local friend id');
      expect(thread.first.emotion, Emotion.happy);
      // Nothing must be filed under the backend id.
      expect(database.loadMessages('backend-bob'), isEmpty);
    });

    test('a duplicate delivery is ignored (LAN + internet race)', () async {
      await database.addFriend(Friend(
        id: 'bob-local',
        name: 'Bob',
        role: UserRole.deaf,
        addedAt: DateTime.now(),
        remoteId: 'backend-bob',
      ));

      Map<String, dynamic> wire() => <String, dynamic>{
            'type': 'chat',
            'id': 'm-same',
            'senderId': 'bob-local',
            'senderName': 'Bob',
            'receiverId': 'local-me',
            'originalText': 'hi',
            'translatedText': 'Hi.',
            'direction': 'deafToBlind',
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'sent',
            'readByReceiver': false,
          };

      await chat.handleTransportEvent(wire());
      await chat.handleTransportEvent(wire());

      expect(database.loadMessages('bob-local'), hasLength(1));
    });

    test('a message from a non-friend is refused', () async {
      await chat.handleTransportEvent(<String, dynamic>{
        'type': 'chat',
        'id': 'm-stranger',
        'senderId': 'backend-stranger',
        'senderName': 'Stranger',
        'receiverId': 'local-me',
        'originalText': 'hi',
        'translatedText': 'Hi.',
        'direction': 'deafToBlind',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'sent',
        'readByReceiver': false,
      });

      expect(database.loadMessages('backend-stranger'), isEmpty);
    });
  });
}

/// Builds an unsigned three-part JWT with the given payload, which is all the
/// config guard needs to inspect.
String _jwt(Map<String, dynamic> payload) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(<String, dynamic>{'alg': 'HS256'})}.${part(payload)}.signature';
}

ChatMessage _message({
  required String id,
  required String from,
  required String to,
  String text = 'hello',
}) {
  return ChatMessage(
    id: id,
    senderId: from,
    senderName: 'Someone',
    receiverId: to,
    originalText: text,
    translatedText: text,
    direction: MessageDirection.deafToBlind,
    timestamp: DateTime.now(),
  );
}

/// Fails loudly, to prove one bad transport cannot take the others down.
class _ThrowingTransport implements ChatTransport {
  @override
  Stream<Map<String, dynamic>> get events =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  void updateIdentity(Map<String, dynamic> identity) {}

  @override
  Future<bool> sendToFriend(
    String friendId,
    Map<String, dynamic> payload,
  ) async {
    throw StateError('transport exploded');
  }
}
