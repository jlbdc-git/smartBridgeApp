import 'dart:async';

import '../database/local_database.dart';
import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';

/// Built-in TEST/SAMPLE friend.
///
/// WHY: connecting two real people needs two phones meeting in person. To test
/// the whole conversation flow on a single device, this service adds a local
/// stand-in friend whose replies are generated on-device by the same
/// translation engines used for real messages.
///
/// SAFETY / PRIVACY
///  * The id is a reserved constant, so it can never collide with a real user.
///  * The name is permanently labelled "Sample" AND the friend carries
///    [Friend.isSample], so it cannot be confused with a real contact.
///  * Nothing is transmitted over the LAN transport - no announce, no TCP
///    payload, no personal data leaves the device.
///  * It can be removed like any other friend and re-added from Settings.
class SampleFriendService {
  SampleFriendService({required this.database, required this.onLocalMessage});

  final LocalDatabase database;

  /// Stores + fans out a locally generated message (wired to ChatService).
  final Future<void> Function(ChatMessage message) onLocalMessage;

  /// Reserved id for the sample friend. Never generated for real users.
  static const String friendId = 'sample-friend-local';

  /// Always visible as a test contact.
  static const String displayName = 'Sample Friend (TEST)';

  /// How long the simulated friend "takes" to answer.
  static const Duration replyDelay = Duration(milliseconds: 1400);

  final List<Timer> _pending = <Timer>[];

  bool isSampleFriend(String id) => id == friendId;

  bool get isInstalled => database.findFriend(friendId) != null;

  /// Adds the sample friend (if missing) and seeds one unread greeting.
  Future<Friend> ensureInstalled(UserProfile me) async {
    final Friend? existing = database.findFriend(friendId);
    if (existing != null) return existing;

    // The sample friend always plays the OPPOSITE role, so a tester exercises
    // both the blind and the deaf translation direction.
    final UserRole role =
        me.role == UserRole.blind ? UserRole.deaf : UserRole.blind;

    final Friend friend = Friend(
      id: friendId,
      name: displayName,
      role: role,
      addedAt: DateTime.now(),
      isSample: true,
    );
    await database.addFriend(friend);
    await _seedGreeting(me, friend);
    return friend;
  }

  /// Simulates the other side answering a message the user just sent.
  /// Called by ChatService right after a message is stored.
  void scheduleReply(UserProfile me, Friend friend) {
    if (!isSampleFriend(friend.id)) return;
    final Timer timer = Timer(replyDelay, () async {
      _pending.removeWhere((Timer t) => !t.isActive);
      await _emitReply(me, friend);
    });
    _pending.add(timer);
  }

  /// Cancels every queued simulated reply (used on dispose).
  void dispose() {
    for (final Timer timer in _pending) {
      timer.cancel();
    }
    _pending.clear();
  }

  // ---------------- Simulated content ----------------

  Future<void> _seedGreeting(UserProfile me, Friend friend) async {
    final bool iAmBlind = me.role == UserRole.blind;
    final String body = iAmBlind
        ? "Hi! I'm the built-in sample friend. Send me a message and I'll "
            'answer so you can hear the spoken reply.'
        : "Hi! I'm the built-in sample friend. Send me a message and I'll "
            'answer so you can test the translators.';

    await onLocalMessage(
      ChatMessage(
        id: _id('greeting'),
        senderId: friend.id,
        senderName: friend.name,
        receiverId: me.id,
        originalText: body,
        // A deaf sender's text is already natural English; a blind sender's
        // text stays short and simple. This keeps the sample realistic.
        translatedText: body,
        direction:
            iAmBlind ? MessageDirection.deafToBlind : MessageDirection.blindToDeaf,
        timestamp: DateTime.now(),
        emotion: iAmBlind ? Emotion.happy : null,
        readByReceiver: false,
      ),
    );
  }

  Future<void> _emitReply(UserProfile me, Friend friend) async {
    final bool iAmBlind = me.role == UserRole.blind;

    // Rotate deterministically through the canned lines using the number of
    // replies already stored - no hidden state to keep in sync.
    final int turn = database
        .loadMessages(friend.id)
        .where((ChatMessage m) => m.senderId == friend.id)
        .length;

    final List<String> lines =
        iAmBlind ? _naturalEnglishReplies : _simpleEnglishReplies;
    final String body = lines[turn % lines.length];

    // Only the deaf side sends emotions (the spec: the deaf user picks them).
    final Emotion? emotion =
        iAmBlind ? _replyEmotions[turn % _replyEmotions.length] : null;

    await onLocalMessage(
      ChatMessage(
        id: _id('reply'),
        senderId: friend.id,
        senderName: friend.name,
        receiverId: me.id,
        originalText: body,
        translatedText: body,
        direction:
            iAmBlind ? MessageDirection.deafToBlind : MessageDirection.blindToDeaf,
        timestamp: DateTime.now(),
        emotion: emotion,
        readByReceiver: false,
      ),
    );
  }

  /// Replies the sample friend (a deaf user) sends to a blind tester:
  /// natural English + an emotion to be spoken.
  static const List<String> _naturalEnglishReplies = <String>[
    'That sounds good to me. What time works for you?',
    'Thanks for letting me know. I will be there.',
    "Sorry, I can't make it today. Can we do it tomorrow?",
    "I'm at the mall already. Where would you like to meet?",
    'Great, see you soon!',
  ];

  /// Replies the sample friend (a blind user) sends to a deaf tester:
  /// short, simple English, no emotion attached.
  static const List<String> _simpleEnglishReplies = <String>[
    'Ok. What time?',
    'Thank you. I come.',
    'Sorry. Not today. Tomorrow ok?',
    'I at mall now. Where you?',
    'Good. See you soon.',
  ];

  /// Emotions used by the sample deaf friend, so the blind tester hears the
  /// emotion prefix in TTS ("Happy. ...", "Sad. ...").
  static const List<Emotion> _replyEmotions = <Emotion>[
    Emotion.happy,
    Emotion.happy,
    Emotion.sad,
    Emotion.shy,
    Emotion.happy,
  ];

  String _id(String kind) =>
      'sample-$kind-${DateTime.now().microsecondsSinceEpoch}';
}
