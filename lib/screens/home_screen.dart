import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Role-adaptive home.
///
/// Blind mode: three giant spoken buttons (voice message, read messages,
/// friends). Deaf mode: the conversation list with a visible notification bar.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.session,
    required this.onOpenTranslator,
    required this.onOpenSettings,
    required this.unreadCount,
  });

  final SessionService session;
  final VoidCallback onOpenTranslator;
  final VoidCallback onOpenSettings;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final UserProfile me = session.profile!;

    return me.role == UserRole.blind
        ? _BlindHome(
            session: session,
            onOpenTranslator: onOpenTranslator,
            onOpenSettings: onOpenSettings,
            unreadCount: unreadCount,
          )
        : _DeafHome(
            session: session,
            onOpenSettings: onOpenSettings,
            unreadCount: unreadCount,
          );
  }
}

// ---------------------------------------------------------------------------
// BLIND home: audio-first, three giant buttons
// ---------------------------------------------------------------------------

class _BlindHome extends StatelessWidget {
  const _BlindHome({
    required this.session,
    required this.onOpenTranslator,
    required this.onOpenSettings,
    required this.unreadCount,
  });

  final SessionService session;
  final VoidCallback onOpenTranslator;
  final VoidCallback onOpenSettings;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hello, ${session.profile!.name}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              'What would you like to do?',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 20),
            BigButton(
              label: 'Send a voice message',
              icon: Icons.mic_rounded,
              subtext: 'Speak, check the simplified text, send',
              onPressed: onOpenTranslator,
            ),
            const SizedBox(height: 14),
            BigButton(
              label: unreadCount > 0
                  ? 'Read $unreadCount new message${unreadCount == 1 ? '' : 's'}'
                  : 'Read my messages',
              icon: Icons.hearing,
              subtext: 'Opens the last conversation',
              onPressed: () => _openLastConversation(context),
            ),
            const SizedBox(height: 14),
            BigButton(
              label: 'My friends',
              icon: Icons.group_rounded,
              subtext: 'Add a friend or manage your list',
              onPressed: () => _openFriends(context),
            ),
            const SizedBox(height: 14),
            BigButton(
              label: 'Settings',
              icon: Icons.settings_rounded,
              onPressed: onOpenSettings,
            ),
            const SizedBox(height: 24),
            Text(
              'Tip: every button is announced. Your friends must be on the '
              'same Wi-Fi for live chat; messages you send while offline are '
              'kept and delivered later.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLastConversation(BuildContext context) async {
    final List<Friend> friends = session.database.loadFriends();
    if (friends.isEmpty) {
      await session.tts.speakConfirmation(
        'You have no friends yet. Open my friends to add one.',
      );
      if (context.mounted) {
        Navigator.of(context).pushNamed('/friends');
      }
      return;
    }
    // Most recent conversation = friend with the latest stored message.
    String? lastFriendId;
    DateTime? lastTime;
    for (final Friend friend in friends) {
      final messages = session.database.loadMessages(friend.id);
      if (messages.isNotEmpty) {
        final DateTime time = messages.last.timestamp;
        if (lastTime == null || time.isAfter(lastTime)) {
          lastTime = time;
          lastFriendId = friend.id;
        }
      }
    }
    final String target = lastFriendId ?? friends.first.id;
    await session.tts.speakConfirmation('Opening conversation.');
    if (context.mounted) {
      Navigator.of(context).pushNamed('/chat', arguments: target);
    }
  }

  Future<void> _openFriends(BuildContext context) async {
    await session.tts.speakConfirmation('Opening friends.');
    if (context.mounted) {
      Navigator.of(context).pushNamed('/friends');
    }
  }
}

// ---------------------------------------------------------------------------
// DEAF home: visual conversation list + big add-friend action
// ---------------------------------------------------------------------------

class _DeafHome extends StatelessWidget {
  const _DeafHome({
    required this.session,
    required this.onOpenSettings,
    required this.unreadCount,
  });

  final SessionService session;
  final VoidCallback onOpenSettings;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<Friend> friends = session.database.loadFriends();

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${session.profile!.name}'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: onOpenSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'deafHomeFab',
        onPressed: () => Navigator.of(context).pushNamed('/add-friend'),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add friend'),
      ),
      body: Column(
        children: [
          if (unreadCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.mark_email_unread_rounded,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$unreadCount new message${unreadCount == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: friends.isEmpty
                ? EmptyState(
                    icon: Icons.group_add_rounded,
                    title: 'No friends yet',
                    subtitle:
                        'Meet in person, then scan their QR code or type their code.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: friends.length,
                    itemBuilder: (BuildContext context, int index) {
                      final Friend friend = friends[index];
                      final messages =
                          session.database.loadMessages(friend.id);
                      final String preview = messages.isEmpty
                          ? 'Say hi!'
                          : messages.last.displayText;
                      final int unread = messages
                          .where((m) =>
                              m.senderId == friend.id && !m.readByReceiver)
                          .length;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            radius: 26,
                            child: Text(
                              friend.name.isNotEmpty
                                  ? friend.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w900),
                            ),
                          ),
                          title: Text(
                            friend.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17),
                          ),
                          subtitle: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: unread > 0
                              ? CircleAvatar(
                                  radius: 12,
                                  backgroundColor: scheme.primary,
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                )
                              : null,
                          onTap: () => Navigator.of(context)
                              .pushNamed('/chat', arguments: friend.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
