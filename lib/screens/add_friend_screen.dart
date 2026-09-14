import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/user_profile.dart';
import '../services/friend_service.dart';
import '../services/session_service.dart';
import '../widgets/accessibility.dart';

/// Add Friend screen.
///
/// Tab 1 (Show my QR): my expiring invite code as QR + readable text.
/// Tab 2 (Scan / type code): camera scanner or manual code entry, then
/// mutual confirmation with a preview of who is connecting.
///
/// No public search exists anywhere in the app: connecting requires two
/// people standing next to each other.
class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key, required this.session});

  final SessionService session;

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _codeController = TextEditingController();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      if (mounted) setState(() {}); // drives the countdown text
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabs.dispose();
    _codeController.dispose();
    super.dispose();
  }

  SessionService get _session => widget.session;
  FriendService get _friends => _session.friendService;

  String get _myCode => _friends.getOrCreateInviteCode(_session.profile!);

  String _formatCountdown(int secondsLeft) {
    final int minutes = secondsLeft ~/ 60;
    final int seconds = secondsLeft % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  // ---------------- Flow: enter / scan a code ----------------

  Future<void> _submitCode(String raw) async {
    final UserProfile me = _session.profile!;
    final InviteCheckResult result = _friends.checkInvite(raw, me: me);

    switch (result) {
      case InviteCheckResult.invalid:
        _showError('Invalid or expired friend code.');
        return;
      case InviteCheckResult.selfInvite:
        _showError('That is your own code. Share it with a friend!');
        return;
      case InviteCheckResult.expired:
        _showError('Invalid or expired friend code.');
        return;
      case InviteCheckResult.removed:
      case InviteCheckResult.ok:
        break;
    }

    // QR payloads carry the full identity; typed codes resolve the name
    // during confirmation (the other side sends its hello payload).
    final Map<String, dynamic>? qr = _tryParseQr(raw);
    String friendName = 'Friend';
    UserRole friendRole = me.role == UserRole.blind
        ? UserRole.deaf
        : UserRole.blind; // sensible default until hello exchange
    String friendId = raw.trim().toUpperCase();

    if (qr != null) {
      friendId = (qr['id'] ?? friendId) as String;
      friendName = (qr['name'] ?? friendName) as String;
      final String? role = qr['role'] as String?;
      if (role == 'blind') friendRole = UserRole.blind;
      if (role == 'deaf') friendRole = UserRole.deaf;
    }

    final bool? confirmed = await _showConfirmDialog(
      name: friendName,
      role: friendRole,
    );
    if (confirmed != true || !mounted) return;

    await _friends.confirmFriendship(
      friendId: friendId,
      friendName: friendName,
      friendRole: friendRole,
    );

    if (_session.profile?.role == UserRole.blind) {
      await _session.tts.speakConfirmation('$friendName is now your friend.');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$friendName is now your friend')),
    );
    Navigator.of(context).pop();
  }

  Map<String, dynamic>? _tryParseQr(String raw) {
    final String input = raw.trim();
    if (!input.startsWith('{')) return null;
    try {
      final Object? decoded = jsonDecode(input);
      if (decoded is Map<String, dynamic> && decoded['app'] == 'smartbridge') {
        return decoded;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<bool?> _showConfirmDialog({
    required String name,
    required UserRole role,
  }) {
    final String roleLabel =
        role == UserRole.blind ? 'blind user' : 'deaf user';
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Confirm connection'),
        content: Text(
          'Connect with $name ($roleLabel)?\n\n'
          'They will appear in your friends list and you can start chatting. '
          'Both of you must confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
    if (_session.profile?.role == UserRole.blind) {
      _session.tts.speakConfirmation(message);
    }
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final bool blindMode = _session.profile?.role == UserRole.blind;
    final int secondsLeft = _friends.inviteSecondsLeft();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a friend'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_2_rounded), text: 'Show my code'),
            Tab(icon: Icon(Icons.qr_code_scanner_rounded), text: 'Scan code'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ---------------- Tab 1: show my QR ----------------
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Meet in person, then let your friend scan this code. '
                'It expires after 30 minutes for your safety.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: QrImageView(
                    data: _friends
                        .buildInviteQrPayload(_session.profile!, _myCode),
                    size: 220,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Column(
                  children: [
                    Text(
                      'or share this code',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _myCode,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      secondsLeft > 0
                          ? 'Expires in ${_formatCountdown(secondsLeft)}'
                          : 'Code expired - it refreshes automatically',
                      style: TextStyle(
                        color: secondsLeft > 60
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (blindMode) ...[
                const SizedBox(height: 24),
                BigButton(
                  label: 'Read my code aloud',
                  icon: Icons.volume_up_rounded,
                  onPressed: () => _session.tts.speakConfirmation(
                    'Your friend code is ${_myCode.replaceAll('-', ' ')}.',
                  ),
                ),
              ],
            ],
          ),
          // ---------------- Tab 2: scan / type ----------------
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Your friend shows their code. Scan the QR or type the '
                'short code they see on their screen.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: 'Scan QR code',
                icon: Icons.photo_camera_rounded,
                subtext: 'Camera opens only when you tap this',
                onPressed: () async {
                  final String? scanned = await showDialog<String>(
                    context: context,
                    builder: (_) => const _QrScanDialog(),
                  );
                  if (scanned != null && mounted) {
                    await _submitCode(scanned);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Type the code instead',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'SB-0000-00',
                ),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'Connect',
                icon: Icons.how_to_reg_rounded,
                onPressed: () => _submitCode(_codeController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fullscreen camera scanner. The camera is ONLY started after the user
/// explicitly tapped "Scan QR code" (privacy: request permission when needed).
class _QrScanDialog extends StatefulWidget {
  const _QrScanDialog();

  @override
  State<_QrScanDialog> createState() => _QrScanDialogState();
}

class _QrScanDialogState extends State<_QrScanDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Scan friend code'),
          backgroundColor: Colors.black,
        ),
        body: MobileScanner(
          controller: _controller,
          onDetect: (BarcodeCapture capture) {
            if (_handled) return;
            for (final Barcode barcode in capture.barcodes) {
              final String? value = barcode.rawValue;
              if (value == null || value.isEmpty) continue;
              _handled = true;
              Navigator.of(context).pop(value);
              return;
            }
          },
        ),
      ),
    );
  }
}
