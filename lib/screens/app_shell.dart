import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/ui_preferences.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../services/session_service.dart';
import 'add_friend_screen.dart';
import 'blind_translator_screen.dart';
import 'chat_screen.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import 'home_screen.dart';
import 'legacy/about_screen.dart' as legacy;
import 'settings_screen.dart';

/// Root navigation shell after setup.
///
/// Owns routes, the offline banner, new-message announcements (deaf mode)
/// and spoken confirmations (blind mode).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.prefs,
    required this.onPreferencesChanged,
  });

  final SessionService session;

  /// Current UI preferences owned by MyApp (the theme layer).
  final AppUiPreferences prefs;

  /// Hands an updated preference object back to MyApp, which rebuilds the
  /// MaterialApp immediately (text scale / theme / contrast).
  final ValueChanged<AppUiPreferences> onPreferencesChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _homeIndex = 0;
  StreamSubscription<ChatMessage>? _incomingSub;
  StreamSubscription<void>? _profileSub;

  @override
  void initState() {
    super.initState();
    _incomingSub = widget.session.chatService.incomingMessages.listen(
      _onIncoming,
    );
    // A role or name change (Settings -> Profile) must re-render the home
    // immediately: blind and deaf homes are different screens entirely.
    _profileSub = widget.session.profileEvents.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  SessionService get _session => widget.session;

  void _onIncoming(ChatMessage message) {
    if (!mounted) return;
    setState(() {}); // refresh unread badges

    // The open chat screen already reads/vibrates for its own messages.
    if (_session.openChatFriendId == message.senderId) return;

    if (_session.profile?.role == UserRole.blind) {
      // Spoken alert with the sender's name; the chat screen reads the body.
      _session.tts.speakConfirmation(
        'New message from ${message.senderName}.',
      );
      return;
    }

    // Deaf mode: tactile + visual notification. No information depends on
    // sound alone.
    if (_session.shouldVibrateOnIncoming) {
      HapticFeedback.vibrate();
    }
    if (_session.notificationsEnabled) {
      _showIncomingBanner(message);
    }
  }

  /// Visual new-message banner with a shortcut into the conversation.
  void _showIncomingBanner(ChatMessage message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          'New message from ${message.senderName}\n${message.displayText}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () =>
              Navigator.of(context).pushNamed('/chat', arguments: message.senderId),
        ),
      ),
    );
  }

  /// Adds the built-in TEST contact and refreshes the home list.
  Future<void> _addSampleFriend() async {
    await _session.addSampleFriend();
    if (mounted) setState(() {});
  }

  void _openTranslator() {
    final List<Friend> friends = _session.database.loadFriends();
    if (friends.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a friend first to send a voice message')),
      );
      Navigator.of(context).pushNamed('/friends');
      return;
    }
    Navigator.of(context)
        .pushNamed('/translator', arguments: friends.first.id);
  }



  @override
  Widget build(BuildContext context) {
    final UserProfile? profile = _session.profile;
    if (profile == null) {
      // Should not happen (the setup gate guarantees a profile).
      return const SizedBox.shrink();
    }

    // Android back button: leave the Settings tab before leaving the app.
    return PopScope(
      canPop: _homeIndex == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_homeIndex != 0) setState(() => _homeIndex = 0);
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      body: IndexedStack(
        index: _homeIndex,
        children: <Widget>[
          HomeScreen(
            session: _session,
            onOpenTranslator: _openTranslator,
            onOpenSettings: () => setState(() => _homeIndex = 1),
            onAddSampleFriend: _addSampleFriend,
            unreadCount: _session.unreadCount(),
          ),
          AppSettingsScreen(
            session: _session,
            onBack: () => setState(() => _homeIndex = 0),
            onPreferencesChanged: (AppUiPreferences next) {
              // Single source of truth: the session keeps memory + disk + the
              // TTS engine in sync, and MyApp re-themes instantly so the new
              // font size / contrast / theme applies without a restart.
              _session.updateUiPreferences(next);
              widget.onPreferencesChanged(next);
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }
}

/// Wraps the shell with named routes + offline listening.
class AppRoot extends StatefulWidget {
  const AppRoot({
    super.key,
    required this.session,
    required this.prefs,
    required this.onPreferencesChanged,
  });

  final SessionService session;
  final AppUiPreferences prefs;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  StreamSubscription<bool>? _offlineSub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _offline = widget.session.connectivity.isOffline;
    _offlineSub = widget.session.connectivity.offlineStream.listen((bool offline) {
      if (!mounted) return;
      setState(() => _offline = offline);
      if (offline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "You're offline. Messages will be synchronized when connection is restored.",
            ),
          ),
        );
      }
    });
    widget.session.startTransport();
  }

  @override
  void dispose() {
    _offlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onGenerateRoute: (RouteSettings settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute<void>(
              builder: (BuildContext context) => _OfflineBanner(
                offline: _offline,
                child: AppShell(
                  session: widget.session,
                  prefs: widget.prefs,
                  onPreferencesChanged: widget.onPreferencesChanged,
                ),
              ),
            );
          case '/friends':
            return MaterialPageRoute<void>(
              builder: (BuildContext context) => _OfflineBanner(
                offline: _offline,
                child: FriendsScreen(session: widget.session),
              ),
            );
          case '/add-friend':
            return MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  AddFriendScreen(session: widget.session),
            );
          case '/friend-requests':
            return MaterialPageRoute<void>(
              builder: (BuildContext context) =>
                  FriendRequestsScreen(session: widget.session),
            );
          case '/chat':
            final String friendId = settings.arguments as String;
            return MaterialPageRoute<void>(
              builder: (BuildContext context) => _OfflineBanner(
                offline: _offline,
                child: ChatScreen(
                  session: widget.session,
                  friendId: friendId,
                ),
              ),
            );
          case '/translator':
            final String friendId = settings.arguments as String;
            return MaterialPageRoute<void>(
              builder: (BuildContext context) {
                final Friend? friend =
                    widget.session.database.findFriend(friendId);
                return BlindTranslatorScreen(
                  session: widget.session,
                  friendName: friend?.name ?? 'friend',
                  friendId: friendId,
                );
              },
            );
          case '/about':
            return MaterialPageRoute<void>(
              builder: (BuildContext context) => const legacy.AboutScreen(),
            );
          case '/setup':
          default:
            return MaterialPageRoute<void>(
              builder: (BuildContext context) => _OfflineBanner(
                offline: _offline,
                child: AppShell(
                  session: widget.session,
                  prefs: widget.prefs,
                  onPreferencesChanged: widget.onPreferencesChanged,
                ),
              ),
            );
        }
      },
    );
  }
}

/// Thin offline banner wrapper shown on every main screen.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.offline, required this.child});

  final bool offline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (offline)
          Material(
            color: const Color(0xFFB45309),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: const [
                    SizedBox(width: 16),
                    Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "You're offline. Messages will be synchronized when connection is restored.",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: child),
      ],
    );
  }
}
