import 'package:permission_handler/permission_handler.dart' as permissions;

/// Microphone permission helper for voice messages (speech-to-text).
///
/// The camera permission used by the removed sign-recognition feature is gone;
/// the QR code scanner requests camera access through its own plugin.
class PermissionHandler {
  /// Requests microphone permission. Returns true when granted.
  static Future<bool> requestMicrophonePermission() async {
    final permissions.PermissionStatus status =
        await permissions.Permission.microphone.request();
    return status.isGranted;
  }

  /// Opens the OS app settings so the user can grant a denied permission.
  static Future<void> openAppSettingsPage() async {
    await permissions.openAppSettings();
  }
}
