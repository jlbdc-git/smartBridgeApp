import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/remote_backend.dart';
import '../models/user_profile.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Friend Requests.
///
/// One place with the full connection state, read from the server (so it is
/// correct after a restart) and kept live by the backend's realtime streams:
///
///   * PENDING  - incoming requests waiting for MY answer (Accept / Decline)
///                and outgoing requests waiting for the OTHER side.
///   * FRIENDS  - accepted: both sides can chat.
///   * DECLINED - requests the user (or they) declined; shown read-only with
///                a hint that a new request can revive the connection.
///
/// Only the invited side can accept or decline (enforced by the database, not
/// this UI). Accessibility: blind mode gets TTS announcements and large
/// buttons; deaf mode gets clear labels, icons and no sound-only information.
class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key, required this.session});

  final SessionService session;

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  List<RemoteFriendship> _rows = <RemoteFriendship>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  StreamSubscription<RemoteRequest>? _requestSub;
  StreamSubscription<RemoteFriendship>? _updatesSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Live updates without manual refresh: a brand-new incoming request and
    // an accept/decline of MY outgoing request both arrive as events.
    _requestSub = widget.session.backend?.incomingRequests.listen((_) => _load());
    _updatesSub = widget.session.backend?.friendshipUpdates.listen((_) => _load());
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    _updatesSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final RemoteBackend? backend = widget.session.backend;
    if (backend == null || backend.state != BackendState.ready) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'The internet connection to the server is not available '
              'right now.';
        });
      }
      return;
    }
    try {
      final List<RemoteFriendship> rows = await backend.listMyRequests();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the requests. Please try again later.';
        });
      }
    }
  }

  List<RemoteFriendship> get _incomingPending => _rows
      .where((RemoteFriendship r) =>
          r.incoming && r.status == RemoteFriendshipStatus.pending)
      .toList();

  List<RemoteFriendship> get _outgoingPending => _rows
      .where((RemoteFriendship r) =>
          !r.incoming && r.status == RemoteFriendshipStatus.pending)
      .toList();

  List<RemoteFriendship> get _accepted => _rows
      .where((RemoteFriendship r) => r.status == RemoteFriendshipStatus.confirmed)
      .toList();

  List<RemoteFriendship> get _declined => _rows
      .where((RemoteFriendship r) => r.status == RemoteFriendshipStatus.declined)
      .toList();

  Future<void> _accept(RemoteFriendship request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bool ok =
          await widget.session.acceptFriendRequest(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${request.peer.displayName} is now your friend'
                : 'Could not accept the request. Please try again.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(RemoteFriendship request) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bool ok =
          await widget.session.declineFriendRequest(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Request from ${request.peer.displayName} declined'
                : 'Could not decline the request. Please try again.',
          ),
        ),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Friend requests')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        color: scheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            _error!,
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ),
                    ),
                  if (!_hasAnything)
                    const EmptyState(
                      icon: Icons.mark_email_unread_outlined,
                      title: 'No friend requests',
                      subtitle:
                          'When somebody scans your code and sends a request, '
                          'it appears here for you to accept or decline.',
                    ),
                  _section(
                    context,
                    title: 'Waiting for your answer',
                    visible: _incomingPending.isNotEmpty,
                    children: <Widget>[
                      for (final RemoteFriendship request in _incomingPending)
                        _requestCard(context, request),
                    ],
                  ),
                  _section(
                    context,
                    title: 'Sent - waiting for them to accept',
                    visible: _outgoingPending.isNotEmpty,
                    children: <Widget>[
                      for (final RemoteFriendship request in _outgoingPending)
                        _requestCard(context, request),
                    ],
                  ),
                  _section(
                    context,
                    title: 'Friends',
                    visible: _accepted.isNotEmpty,
                    children: <Widget>[
                      for (final RemoteFriendship friend in _accepted)
                        _personCard(
                          context,
                          friend,
                          trailing: const Icon(
                            Icons.handshake_rounded,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                  _section(
                    context,
                    title: 'Declined',
                    visible: _declined.isNotEmpty,
                    children: <Widget>[
                      for (final RemoteFriendship request in _declined)
                        _personCard(
                          context,
                          request,
                          subtitle: request.incoming
                              ? 'You declined this request. A new request '
                                  'from them can revive the connection.'
                              : 'They declined your request. Sending a new '
                                  'request can revive the connection.',
                        ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  bool get _hasAnything =>
      _incomingPending.isNotEmpty ||
      _outgoingPending.isNotEmpty ||
      _accepted.isNotEmpty ||
      _declined.isNotEmpty;

  Widget _section(
    BuildContext context, {
    required String title,
    required bool visible,
    required List<Widget> children,
  }) {
    if (!visible) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _requestCard(BuildContext context, RemoteFriendship request) {
    final bool blindMode = widget.session.profile?.role == UserRole.blind;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${request.peer.displayName} wants to connect with you.',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 4),
            Text(
              request.peer.role == UserRole.blind
                  ? 'Blind user - sent you a friend request'
                  : 'Deaf user - sent you a friend request',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _accept(request),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _decline(request),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Decline'),
                  ),
                ),
              ],
            ),
            if (blindMode) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Accept lets you and ${request.peer.displayName} chat. '
                'Decline keeps you disconnected.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _personCard(
    BuildContext context,
    RemoteFriendship row, {
    Widget? trailing,
    String? subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          child: Text(
            row.peer.displayName.isNotEmpty
                ? row.peer.displayName[0].toUpperCase()
                : '?',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        title: Text(
          row.peer.displayName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        subtitle: Text(
          subtitle ??
              (row.peer.role == UserRole.blind ? 'Blind user' : 'Deaf user'),
        ),
        trailing: trailing,
      ),
    );
  }
}
