import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Friends list. Blind mode reads entries aloud when tapped and offers big
/// actions; deaf mode is a standard visual list. Removal always asks twice.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.session});

  final SessionService session;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late List<Friend> _friends;

  @override
  void initState() {
    super.initState();
    _friends = widget.session.database.loadFriends();
    _announceListIfBlind();
  }

  Future<void> _announceListIfBlind() async {
    if (widget.session.profile?.role != UserRole.blind) return;
    final int count = _friends.length;
    await widget.session.tts.speakConfirmation(
      count == 0
          ? 'Your friends list is empty. Tap add friend at the bottom.'
          : 'You have $count friend${count == 1 ? '' : 's'}. '
              'Tap a name to open the chat, or use the buttons to manage.',
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _friends = widget.session.database.loadFriends();
    });
  }

  Future<void> _openChat(Friend friend) async {
    if (widget.session.profile?.role == UserRole.blind) {
      await widget.session.tts
          .speakConfirmation('Opening chat with ${friend.name}.');
    }
    if (mounted) {
      Navigator.of(context).pushNamed('/chat', arguments: friend.id);
    }
  }

  Future<void> _confirmRemove(Friend friend) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Remove friend?'),
        content: Text(
          '${friend.name} will be removed and your conversation will be '
          'deleted. You will need to exchange codes again to reconnect.',
      ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.session.database.removeFriend(friend.id);
      await _refresh();
      if (widget.session.profile?.role == UserRole.blind) {
        await widget.session.tts
            .speakConfirmation('${friend.name} removed.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool blindMode = widget.session.profile?.role == UserRole.blind;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My friends')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'friendsFab',
        onPressed: () async {
          await Navigator.of(context).pushNamed('/add-friend');
          await _refresh();
        },
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('Add friend'),
      ),
      body: _friends.isEmpty
          ? const EmptyState(
              icon: Icons.group_add_rounded,
              title: 'No friends yet',
              subtitle:
                  'You must meet in person to connect. Tap Add friend to show your code.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _friends.length,
              itemBuilder: (BuildContext context, int index) {
                final Friend friend = _friends[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: blindMode ? 10 : 4),
                    leading: CircleAvatar(
                      radius: blindMode ? 30 : 24,
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
                          fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                    subtitle: Text(
                      friend.role == UserRole.blind ? 'Blind user' : 'Deaf user',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove ${friend.name}',
                      icon: Icon(Icons.person_remove_alt_1_rounded,
                          color: scheme.error, size: blindMode ? 30 : 24),
                      onPressed: () => _confirmRemove(friend),
                    ),
                    onTap: () => _openChat(friend),
                  ),
                );
              },
            ),
    );
  }
}
