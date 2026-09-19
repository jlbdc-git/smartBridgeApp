import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../services/translation_service.dart';
import '../widgets/accessibility.dart';
import '../widgets/emotion_badge.dart';
import '../widgets/message_bubble.dart';
import 'blind_translator_screen.dart';
import 'deaf_translator_screen.dart';

/// One-to-one chat between confirmed friends.
///
/// Deaf mode: readable bubbles + composer with emotion picker.
/// Blind mode: same conversation, plus big playback controls that speak every
/// message (emotion first) and voice confirmations on send.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.session, required this.friendId});

  final SessionService session;
  final String friendId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<ChatMessage>? _incomingSub;
  StreamSubscription<String>? _outboxSub;

  Emotion? _selectedEmotion;
  bool _isSpeakingNow = false;

  Friend get _friend {
    final Friend? friend = widget.session.database.findFriend(widget.friendId);
    return friend ??
        Friend(
          id: widget.friendId,
          name: 'Friend',
          role: UserRole.blind,
          addedAt: DateTime.now(),
        );
  }

  bool get _blindMode => widget.session.profile?.role == UserRole.blind;

  List<ChatMessage> get _messages =>
      widget.session.database.loadMessages(widget.friendId);

  @override
  void initState() {
    super.initState();
    // Tell the shell this conversation is on screen so it stops notifying
    // about messages the user is already looking at.
    widget.session.openChatFriendId = widget.friendId;

    // Was anything actually waiting when this conversation was opened? Read it
    // BEFORE marking the thread read, otherwise the answer depends on whether
    // the async write happened to finish first and the spoken greeting would
    // appear only sometimes.
    final bool hadUnread = _messages.any((ChatMessage m) =>
        m.senderId == widget.friendId && !m.readByReceiver);
    widget.session.chatService.markConversationRead(widget.friendId);

    _incomingSub = widget.session.chatService.incomingMessages.listen(
      _onIncoming,
    );
    _outboxSub = widget.session.chatService.outboxEvents.listen((String _) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The "new message" banner is stale once this conversation is on
      // screen, and it would sit on top of the composer. Clear it.
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      // Speak the message that was waiting, once."Happy. I'm really glad you
      // came today."
      if (_blindMode && hadUnread) _speakLastReceived();
    });
  }

  /// Speaks the newest received message, emotion first.
  Future<void> _speakLastReceived() async {
    final List<ChatMessage> received = _messages
        .where((ChatMessage m) => m.senderId == widget.friendId)
        .toList();
    if (received.isEmpty) return;
    await widget.session.chatService.speakReceived(received.last);
  }

  void _onIncoming(ChatMessage message) {
    if (message.senderId != widget.friendId) return;
    if (mounted) setState(() {});
    _scrollToBottom();

    if (_blindMode) {
      // The user is listening to this conversation right now: mark it read
      // here as well, otherwise the shell's unread badge stays lit.
      widget.session.chatService.markConversationRead(widget.friendId);
      // Auto-read incoming messages with emotion, e.g.
      // "Happy. I'm really glad you came today."
      widget.session.chatService.speakReceived(message);
    } else if (widget.session.shouldVibrateOnIncoming) {
      HapticFeedback.mediumImpact();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------- Playback controls (blind mode) ----------------

  Future<void> _playLast() async {
    final List<ChatMessage> received = _messages
        .where((ChatMessage m) => m.senderId == widget.friendId)
        .toList();
    if (received.isEmpty) {
      await widget.session.tts.speakConfirmation('No messages yet.');
      return;
    }
    setState(() => _isSpeakingNow = true);
    await widget.session.chatService.speakReceived(received.last);
    setState(() => _isSpeakingNow = false);
  }

  Future<void> _replayAll() async {
    final List<ChatMessage> received = _messages
        .where((ChatMessage m) => m.senderId == widget.friendId)
        .toList();
    if (received.isEmpty) {
      await widget.session.tts.speakConfirmation('No messages yet.');
      return;
    }
    setState(() => _isSpeakingNow = true);
    final StringBuffer buffer = StringBuffer();
    for (final ChatMessage message in received) {
      buffer.write('${message.emotion?.spokenPrefix ?? ''} '
          '${message.displayText} ... ');
    }
    await widget.session.tts.speak(buffer.toString());
    setState(() => _isSpeakingNow = false);
  }

  Future<void> _pauseOrResume() async {
    await widget.session.tts.pause();
  }

  Future<void> _stopSpeaking() async {
    await widget.session.tts.stop();
    setState(() => _isSpeakingNow = false);
  }

  // ---------------- Sending ----------------

  /// Blind composer: opens the voice pipeline (Voice -> STT -> simple English
  /// -> Preview -> Send). It performs the send itself, so there is nothing to
  /// do here afterwards except refresh.
  Future<void> _openBlindTranslator() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext context) => BlindTranslatorScreen(
        session: widget.session,
        friendName: _friend.name,
        friendId: widget.friendId,
      ),
    ));
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  /// Deaf composer: opens the typing pipeline (Typed -> natural English ->
  /// Emotion -> Preview -> Send) and sends whatever comes back.
  Future<void> _openDeafTranslator() async {
    final ChatMessage? draft = await Navigator.of(context)
        .push<ChatMessage>(MaterialPageRoute<ChatMessage>(
      builder: (BuildContext context) => DeafTranslatorScreen(
        session: widget.session,
        friendName: _friend.name,
      ),
    ));
    if (draft == null) return;
    await widget.session.chatService.sendMessage(
      friend: _friend,
      originalText: draft.originalText,
      translatedText: draft.translatedText,
      direction: MessageDirection.deafToBlind,
      emotion: draft.emotion,
    );
    if (_blindMode) {
      await widget.session.tts.speakConfirmation('Message sent.');
    }
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  Future<void> _sendQuick(String text) async {
    final String original = text.trim();
    if (original.isEmpty) return;

    // Whatever way a blind user composes, the outgoing message is simplified
    // so the deaf recipient always gets the short form.
    final String outgoing =
        _blindMode ? const BlindTranslator().simplify(original) : original;

    final ChatMessage sent = await widget.session.chatService.sendMessage(
      friend: _friend,
      originalText: original,
      translatedText: outgoing,
      direction: _blindMode
          ? MessageDirection.blindToDeaf
          : MessageDirection.deafToBlind,
      emotion: _blindMode ? null : _selectedEmotion,
    );
    _composer.clear();
    if (!mounted) return;
    // The emotion belongs to ONE message. Leaving it selected silently stamped
    // the same feeling on the next message too, which is exactly the kind of
    // "the app decided how I feel" behaviour the spec forbids.
    if (_selectedEmotion != null) {
      setState(() => _selectedEmotion = null);
    }
    if (_blindMode) {
      await widget.session.tts.speakConfirmation(
        sent.status == MessageStatus.sent
            ? 'Message sent.'
            : "You're offline. Messages will be synchronized when connection "
                'is restored.',
      );
    }
    if (mounted) setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    if (widget.session.openChatFriendId == widget.friendId) {
      widget.session.openChatFriendId = null;
    }
    _incomingSub?.cancel();
    _outboxSub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<ChatMessage> messages = _messages;
    final bool blind = _blindMode;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              child: Text(
                _friend.name.isNotEmpty ? _friend.name[0].toUpperCase() : '?',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _friend.isSample ? '${_friend.name} - SAMPLE' : _friend.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.session.isOffline)
            const StatusBanner(
              message:
                  "You're offline. Messages will be synchronized when "
                  'connection is restored.',
              icon: Icons.wifi_off_rounded,
              color: Color(0xFFB45309),
            ),
          if (_friend.connectionStatus == ConnectionStatus.pending)
            StatusBanner(
              message:
                  'Waiting for ${_friend.name} to accept your friend request. '
                  'Messages will be delivered once accepted.',
              icon: Icons.hourglass_top_rounded,
              color: scheme.primary,
            ),
          Expanded(
            child: messages.isEmpty
                ? EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Say hi to ${_friend.name}',
                    subtitle: blind
                        ? 'Tap the microphone button below.'
                        : 'Tap the write button below.',
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ChatMessage message = messages[index];
                      return MessageBubble(
                        message: message,
                        isMine: message.senderId ==
                            widget.session.profile?.id,
                      );
                    },
                  ),
          ),
          // ---------------- Blind playback bar ----------------
          if (blind)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSpeakingNow)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        'Speaking...',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _BigControl(
                        icon: Icons.play_arrow_rounded,
                        label: 'Play',
                        onTap: _playLast,
                      ),
                      _BigControl(
                        icon: Icons.replay_rounded,
                        label: 'Replay',
                        onTap: _replayAll,
                      ),
                      _BigControl(
                        icon: Icons.pause_rounded,
                        label: 'Pause',
                        onTap: _pauseOrResume,
                      ),
                      _BigControl(
                        icon: Icons.stop_rounded,
                        label: 'Stop',
                        onTap: _stopSpeaking,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // ---------------- Composer ----------------
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                border: Border(
                  top: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Row(
                children: [
                  if (!blind) ...[
                    // Emotion picker chip (deaf mode only).
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _pickEmotion,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _selectedEmotion == null
                            ? Icon(Icons.mood_rounded,
                                size: 28, color: scheme.primary)
                            : EmotionBadge(
                                emotion: _selectedEmotion!,
                                compact: true,
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: blind
                            ? 'Type instead of speaking'
                            : 'Message ${_friend.name}',
                      ),
                      onSubmitted: _sendQuick,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Big translate-and-send button. Blind users get the voice
                  // pipeline, deaf users get the text pipeline.
                  IconButton.filled(
                    onPressed: () async {
                      if (blind) {
                        await widget.session.tts
                            .speakConfirmation('Opening voice message.');
                      }
                      if (!context.mounted) return;
                      await (blind
                          ? _openBlindTranslator()
                          : _openDeafTranslator());
                    },
                    icon: Icon(
                      blind
                          ? Icons.mic_rounded
                          : Icons.auto_fix_high_rounded,
                      size: 26,
                    ),
                    tooltip: blind
                        ? 'Record a voice message'
                        : 'Write with translator',
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: () => _sendQuick(_composer.text),
                    icon: const Icon(Icons.send_rounded, size: 24),
                    tooltip: blind ? 'Send typed message' : 'Send as typed',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickEmotion() async {
    final Emotion? picked = await showModalBottomSheet<Emotion>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'How do you feel? (never guessed automatically)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final Emotion emotion in Emotion.values)
              ListTile(
                leading: Icon(emotion.icon, color: emotion.color, size: 30),
                title: Text(
                  emotion.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18),
                ),
                trailing: _selectedEmotion == emotion
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => Navigator.of(context).pop(emotion),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() => _selectedEmotion = picked);
    }
  }
}

class _BigControl extends StatelessWidget {
  const _BigControl({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: scheme.primary),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
