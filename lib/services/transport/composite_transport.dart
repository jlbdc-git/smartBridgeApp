import 'dart:async';

import '../../backend/remote_backend.dart';
import 'lan_transport.dart';
export '../../backend/remote_backend.dart' show PolicyRefusalException;

/// Presents several transports as one [ChatTransport].
///
/// ORDER MATTERS: [transports] is tried in sequence and the first successful
/// delivery wins. The app is built as `[LAN, internet]`, so two phones on the
/// same Wi-Fi keep talking directly (fast, private, no mobile data) and only
/// friends on a different network fall through to the backend.
///
/// Incoming events from every transport are merged, and duplicates are
/// harmless: `ChatService` de-duplicates by message id, which is also what
/// makes a retry after a lost response safe.
class CompositeChatTransport implements ChatTransport {
  CompositeChatTransport(this.transports);

  final List<ChatTransport> transports;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  final List<StreamSubscription<Map<String, dynamic>>> _subs =
      <StreamSubscription<Map<String, dynamic>>>[];

  bool _listening = false;

  /// Subscribes to every underlying transport. Safe to call twice.
  void start() {
    if (_listening) return;
    _listening = true;
    for (final ChatTransport transport in transports) {
      _subs.add(transport.events.listen(
        (Map<String, dynamic> event) {
          if (!_events.isClosed) _events.add(event);
        },
        // One broken transport must never take the others down.
        onError: (Object _) {},
      ));
    }
  }

  @override
  Stream<Map<String, dynamic>> get events {
    start();
    return _events.stream;
  }

  @override
  void updateIdentity(Map<String, dynamic> identity) {
    for (final ChatTransport transport in transports) {
      transport.updateIdentity(identity);
    }
  }

  /// Delivers to the first transport that can. Returns false when none could,
  /// which leaves the message in the outbox for a later retry.
  @override
  Future<bool> sendToFriend(
    String friendId,
    Map<String, dynamic> payload,
  ) async {
    for (final ChatTransport transport in transports) {
      try {
        if (await transport.sendToFriend(friendId, payload)) return true;
      } on PolicyRefusalException {
        // A row level security refusal is a DEFINITIVE answer from the server
        // ("this friendship is not confirmed"), not a transport failure.
        // It must reach the caller, which demotes the friend link to pending
        // and stops retrying - swallowing it would turn one refusal into an
        // endless retry loop.
        rethrow;
      } catch (_) {
        // Try the next transport.
      }
    }
    return false;
  }

  Future<void> dispose() async {
    for (final StreamSubscription<Map<String, dynamic>> sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    await _events.close();
  }
}
