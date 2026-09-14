import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Conversation list shown as the deaf home body (also reachable generally).
class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, required this.session});

  final SessionService session;

  @override
  Widget build(BuildContext context) {
    final List<Friend> friends = session.database.loadFriends();

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: friends.isEmpty
          ? const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
              subtitle: 'Add a friend to start chatting.',
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: friends.length,
              itemBuilder: (BuildContext context, int index) {
                final Friend friend = friends[index];
                final messages = session.database.loadMessages(friend.id);
                final String preview =
                    messages.isEmpty ? 'Say hi!' : messages.last.displayText;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
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
                    onTap: () =>
                        Navigator.of(context).pushNamed('/chat', arguments: friend.id),
                  ),
                );
              },
            ),
    );
  }
}
