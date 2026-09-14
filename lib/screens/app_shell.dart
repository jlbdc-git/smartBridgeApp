import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../services/session_service.dart';
import 'add_friend_screen.dart';
import 'blind_translator_screen.dart';
import 'chat_screen.dart';
import 'friends_screen.dart';
import 'home_screen.dart';
import 'legacy/about_screen.dart' as legacy;
import 'settings_screen.dart';

/// Root navigation shell after setup.
///
/// Owns routes, the offline banner, new-message announcements (deaf mode)
/// and spoken confirmations (blind mode).
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.session});

  final SessionService session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _homeIndex = 0;
  StreamSubscription<ChatMessage>? _incomingSub;

  @override
  void initState() {
    super.initState();
    _incomingSub = widget.session.chatService.incomingMessages.listen(
      _onIncoming,
    );
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    super.dispose();
  }

  SessionService get _session => widget.session;

  void _onIncoming(ChatMessage message) {
    if (!mounted) return;
    setState(() {}); // refresh unread badges

    final bool blind = _session.profile?.role == UserRole.blind;
    if (blind) {
      // Spoken alert with sender name; the chat screen reads the body.
      _session.tts.speakConfirmation(
        'New message from ${message.senderName}.',
      );
    } else if (_session.vibrationEnabled) {
      // Deaf mode: vibration pattern. No critical info depends on sound.
      // (Visual notification banner shows in home when returning.)
    }
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

    return Scaffold(
      body: IndexedStack(
        index: _homeIndex,
        children: <Widget>[
          HomeScreen(
            session: _session,
            onOpenTranslator: _openTranslator,
            onOpenSettings: () => setState(() => _homeIndex = 1),
            unreadCount: _session.unreadCount(),
          ),
          AppSettingsScreen(
            session: _session,
            onPreferencesChanged: (prefs) async {
              await _session.updateUiPreferences(prefs);
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
  const AppRoot({super.key, required this.session});

  final SessionService session;

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
                child: AppShell(session: widget.session),
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
                child: AppShell(session: widget.session),
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
