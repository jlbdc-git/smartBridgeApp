import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../models/emotion.dart';
import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';
import '../widgets/emotion_badge.dart';
import '../widgets/message_bubble.dart';
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
  Timer? _readTicker;

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
    widget.session.chatService.markConversationRead(widget.friendId);
    _incomingSub = widget.session.chatService.incomingMessages.listen(
      _onIncoming,
    );
    _outboxSub = widget.session.chatService.outboxEvents.listen((String _) {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_blindMode) {
        _announceNewMessages();
        _readTicker = Timer.periodic(
          const Duration(seconds: 2),
          (Timer _) => _checkUnread(),
        );
      }
    });
  }

  /// Speaks unread messages once when the chat opens ("New message from
  /// John. Happy. I'm really glad you came today.")
  Future<void> _announceNewMessages() async {
    final List<ChatMessage> unread = _messages
        .where((ChatMessage m) =>
            m.senderId == widget.friendId && !m.readByReceiver)
        .toList();
    if (unread.isEmpty) return;
    await widget.session.chatService.speakReceived(unread.last);
  }

  /// While the chat is open and blind mode is on, announce anything that
  /// arrives (the shell-level announcement is suppressed for the open chat).
  Future<void> _checkUnread() async {
    final List<ChatMessage> unread = _messages
        .where((ChatMessage m) =>
            m.senderId == widget.friendId && !m.readByReceiver)
        .toList();
    if (unread.isEmpty) return;
    await widget.session.chatService.markConversationRead(widget.friendId);
    await widget.session.chatService.speakReceived(unread.last);
  }

  void _onIncoming(ChatMessage message) {
    if (message.senderId != widget.friendId) return;
    if (mounted) setState(() {});
    _scrollToBottom();
    if (_blindMode) {
      // Auto-read incoming messages with emotion, e.g.
      // "Happy. I'm really glad you came today."
      widget.session.chatService.speakReceived(message);
    } else {
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

  // ---------------- Sending (deaf composer) ----------------

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
    if (text.trim().isEmpty) return;
    await widget.session.chatService.sendMessage(
      friend: _friend,
      originalText: text.trim(),
      translatedText: text.trim(),
      direction: widget.session.profile?.role == UserRole.blind
          ? MessageDirection.blindToDeaf
          : MessageDirection.deafToBlind,
      emotion: _selectedEmotion,
    );
    _composer.clear();
    setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _outboxSub?.cancel();
    _readTicker?.cancel();
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
            CircleAvatar(child: Text(_friend.name[0].toUpperCase())),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _friend.name,
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
                  // Big translate-and-send button.
                  IconButton.filled(
                    onPressed: () async {
                      if (blind) {
                        await widget.session.tts
                            .speakConfirmation('Opening translator.');
                      }
                      if (!context.mounted) return;
                      await _openDeafTranslator();
                    },
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 26),
                    tooltip: 'Write with translator',
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: () => _sendQuick(_composer.text),
                    icon: const Icon(Icons.send_rounded, size: 24),
                    tooltip: 'Send as typed',
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
