import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

import '../database/local_database.dart';
import '../models/ui_preferences.dart';
import '../models/user_profile.dart';
import 'chat_service.dart';
import 'connectivity_service.dart';
import 'friend_service.dart';
import 'transport/lan_transport.dart';
import 'tts_service.dart';

/// Holds the live app state: the user's profile, UI preferences and the local
/// database. One instance is created at startup and passed down the tree.
class SessionService {
  SessionService({
    required this.prefs,
    required this.database,
    required this.tts,
    required this.transport,
    required this.chatService,
    required this.connectivity,
  });

  final SharedPreferences prefs;
  final LocalDatabase database;
  final TtsService tts;
  final LanTransport transport;
  final ChatService chatService;
  final ConnectivityService connectivity;

  /// Friend-code / connection service built on the same storage.
  late final FriendService friendService = FriendService(
    database: database,
    prefs: prefs,
  );

  /// True while the device reports no connectivity (drives the offline UI).
  bool get isOffline => connectivity.isOffline;

  static const String _kOnboardingSeen = 'onboarding_seen';
  static const String _kTermsAccepted = 'accepted_terms';
  static const String _kNotificationsEnabled = 'sb_notifications_enabled';
  static const String _kVibrationEnabled = 'sb_vibration_enabled';

  /// Fired after role/profile changes so the shell can rebuild its chrome.
  final StreamController<void> _profileEvents =
      StreamController<void>.broadcast();

  Stream<void> get profileEvents => _profileEvents.stream;

  UserProfile? _profile;

  UserProfile? get profile => _profile;

  bool get hasProfile => _profile != null;

  AppUiPreferences _ui = const AppUiPreferences();

  AppUiPreferences get ui => _ui;

  /// Seeds the in-memory state from disk. Called once before runApp.
  Future<void> load() async {
    _profile = database.loadProfile();
    _ui = AppUiPreferences.fromSharedPreferences(prefs);
    if (_profile != null) {
      chatService.setMe(_profile!);
    }
  }

  bool _transportStarted = false;

  /// Starts the offline LAN transport (UDP discovery + TCP chat) and the
  /// connectivity monitor. Safe to call multiple times; fails soft when no
  /// network interface is usable.
  Future<void> startTransport() async {
    await connectivity.start();
    if (_transportStarted || _profile == null) return;
    _transportStarted = true;
    await transport.start(<String, dynamic>{
      'id': _profile!.id,
      'name': _profile!.name,
      'role': _profile!.role.name,
      'type': 'announce',
    });
    chatService.startListening();
  }

  /// Total unread received messages across all conversations.
  int unreadCount() {
    int total = 0;
    for (final Friend friend in database.loadFriends()) {
      for (final ChatMessage m in database.loadMessages(friend.id)) {
        if (m.senderId == friend.id && !m.readByReceiver) total++;
      }
    }
    return total;
  }

  /// Creates the initial profile at the end of setup.
  Future<void> completeSetup({
    required String name,
    required UserRole role,
  }) async {
    final UserProfile profile = UserProfile(
      id: _generateId('u'),
      name: name.trim().isEmpty ? 'User' : name.trim(),
      role: role,
    );
    await database.saveProfile(profile);
    _profile = profile;
    _profileEvents.add(null);
  }

  Future<void> updateProfile({String? name, UserRole? role}) async {
    if (_profile == null) return;
    final UserProfile updated = _profile!.copyWith(name: name, role: role);
    await database.saveProfile(updated);
    _profile = updated;
    _profileEvents.add(null);
  }

  Future<void> updateUiPreferences(AppUiPreferences next) async {
    _ui = next;
    await next.save(prefs);
  }

  // ---------------- Notification / vibration toggles ----------------

  bool get notificationsEnabled =>
      prefs.getBool(_kNotificationsEnabled) ?? true;

  bool get vibrationEnabled => prefs.getBool(_kVibrationEnabled) ?? true;

  Future<void> setNotificationsEnabled(bool value) =>
      prefs.setBool(_kNotificationsEnabled, value);

  Future<void> setVibrationEnabled(bool value) =>
      prefs.setBool(_kVibrationEnabled, value);

  // ---------------- Onboarding / terms ----------------

  bool get hasSeenOnboarding => prefs.getBool(_kOnboardingSeen) ?? false;

  bool get hasAcceptedTerms => prefs.getBool(_kTermsAccepted) ?? false;

  Future<void> acceptOnboarding() async {
    await prefs.setBool(_kOnboardingSeen, true);
    await prefs.setBool(_kTermsAccepted, true);
  }

  // ---------------- Privacy ----------------

  /// Wipes all conversations. Friends are kept; codes of removed friends
  /// stay blocked until both users re-confirm a connection.
  Future<void> deleteAllConversations() =>
      database.deleteAllConversations();

  String _generateId(String prefix) {
    final DateTime now = DateTime.now();
    final int millis = now.millisecondsSinceEpoch;
    final int random = DateTime.now().microsecondsSinceEpoch % 100000;
    return '$prefix-$millis-$random';
  }

  void dispose() {
    _profileEvents.close();
    chatService.dispose();
    transport.dispose();
  }
}
