import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Minimal offline monitor for the offline banner: "You're offline. Messages
/// will be synchronized when connection is restored."
class ConnectivityService {
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  bool _isOffline = false;

  bool get isOffline => _isOffline;

  Stream<bool> get offlineStream => _controller.stream;

  Future<void> start() async {
    try {
      // connectivity_plus 6.x returns a list of active results.
      final List<ConnectivityResult> results =
          await Connectivity().checkConnectivity();
      _update(results.isEmpty
          ? ConnectivityResult.none
          : results.first);

      Connectivity().onConnectivityChanged.listen(
        (List<ConnectivityResult> results) {
          if (results.isEmpty) {
            _update(ConnectivityResult.none);
          } else {
            _update(results.first);
          }
        },
      );
    } catch (_) {
      // Platform without connectivity support: assume online, don't nag.
      _isOffline = false;
    }
  }

  void _update(ConnectivityResult result) {
    final bool offline = result == ConnectivityResult.none;
    if (offline == _isOffline) return;
    _isOffline = offline;
    _controller.add(offline);
  }

  void dispose() {
    _controller.close();
  }
}
