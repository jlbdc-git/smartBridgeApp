import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Offline LAN transport used when both users are on the same Wi-Fi network.
///
/// Design (kept deliberately small and understandable):
///  * UDP broadcast on port 45123 announces "I am here, here is my name/id".
///  * Direct TCP connections on port 45124 deliver chat payloads.
///  * Nothing leaves the local network; there is no cloud component.
///
/// If Wi-Fi/LAN is unavailable the app still works: messages are stored
/// locally and marked as pending until the transport can deliver them.
class LanTransport {
  static const int udpPort = 45123;
  static const int tcpPort = 45124;
  static const Duration announceInterval = Duration(seconds: 3);

  RawDatagramSocket? _udp;
  ServerSocket? _tcp;
  Timer? _announceTimer;
  bool _running = false;

  /// My current announce payload (id, name, role, invite code).
  Map<String, dynamic> _identity = <String, dynamic>{};

  /// friendId -> last seen IP address (from discovery or incoming chat).
  final Map<String, String> _addresses = <String, String>{};

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Events: {'type': 'announce'|'chat', ...payload}
  Stream<Map<String, dynamic>> get events => _events.stream;

  bool get isRunning => _running;

  /// Starts the UDP announcer and the TCP listener.
  Future<void> start(Map<String, dynamic> identity) async {
    _identity = identity;
    if (_running) {
      return;
    }
    _running = true;

    // --- UDP discovery ---
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
      );
      _udp!.broadcastEnabled = true;
      _udp!.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final Datagram? packet = _udp!.receive();
        if (packet == null) return;
        _handlePacket(packet);
      });
    } on SocketException catch (e) {
      // Port busy (two instances on this machine) or no network: stay
      // functional, delivery just falls back to the outbox retry.
      debugPrint('LAN transport UDP unavailable: $e');
      _udp = null;
    }

    // --- TCP receiver ---
    try {
      _tcp = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort);
      _tcp!.listen((Socket client) {
        final StringBuffer buffer = StringBuffer();
        client.listen(
          (List<int> data) {
            buffer.write(utf8.decode(data, allowMalformed: true));
            final String text = buffer.toString();
            final int newline = text.indexOf('\n');
            if (newline >= 0) {
              _handleLine(text.substring(0, newline),
                  from: client.remoteAddress.address);
              client.destroy();
            }
          },
          onError: (Object _) => client.destroy(),
          cancelOnError: true,
        );
      });
    } on SocketException catch (e) {
      debugPrint('LAN transport TCP unavailable: $e');
      _tcp = null;
    }

    // --- Periodic announce ---
    _announce();
    _announceTimer = Timer.periodic(announceInterval, (Timer _) => _announce());
  }

  /// Updates the announce identity (e.g. after the profile changed).
  void updateIdentity(Map<String, dynamic> identity) {
    _identity = identity;
    _announce();
  }

  void _announce() {
    final RawDatagramSocket? udp = _udp;
    if (udp == null || _identity.isEmpty) return;
    try {
      final List<int> payload =
          utf8.encode(jsonEncode(<String, dynamic>{..._identity, 'type': 'announce'}));
      udp.send(payload, InternetAddress('255.255.255.255'), udpPort);
    } on SocketException catch (_) {
      // Broadcast can fail on networks that block it; ignore silently.
    }
  }

  void _handlePacket(Datagram packet) {
    try {        final Map<String, dynamic> message =
            (jsonDecode(utf8.decode(packet.data)) as Map<String, dynamic>)
                .cast<String, dynamic>();
      if (message['id'] == _identity['id']) return; // my own echo
      _addresses[message['id'] as String? ?? ''] = packet.address.address;
      _events.add(message);
    } catch (_) {
      // Malformed packet: ignore.
    }
  }

  void _handleLine(String line, {required String from}) {
    try {
      final Map<String, dynamic> message =
          (jsonDecode(line) as Map<String, dynamic>).cast<String, dynamic>();
      if (message['id'] is String) {
        _addresses[message['id'] as String] = from;
      }
      _events.add(message);
    } catch (_) {
      // Malformed payload: ignore.
    }
  }

  /// Sends [payload] (JSON) to [address] over TCP. Fast-fails so the caller
  /// can mark the message as pending.
  Future<bool> sendToAddress(
    String address,
    Map<String, dynamic> payload,
  ) async {
    try {
      final Socket socket = await Socket.connect(
        address,
        tcpPort,
        timeout: const Duration(seconds: 3),
      );
      socket.writeln(jsonEncode(payload));
      await socket.flush();
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Best-effort direct delivery to a known friend address.
  Future<bool> sendToFriend(String friendId, Map<String, dynamic> payload) {
    final String? address = _addresses[friendId];
    if (address == null) return Future<bool>.value(false);
    return sendToAddress(address, payload);
  }

  String? addressOf(String friendId) => _addresses[friendId];

  /// Called when a direct send fails: forget the address so discovery can
  /// refresh it.
  void forgetAddress(String friendId) {
    _addresses.remove(friendId);
  }

  void dispose() {
    _announceTimer?.cancel();
    _udp?.close();
    _tcp?.close();
    _running = false;
    _events.close();
  }
}
