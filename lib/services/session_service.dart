import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend_config.dart';
import '../backend/remote_backend.dart';
import '../database/local_database.dart';
import '../models/chat_message.dart';
import '../models/ui_preferences.dart';
import '../models/user_profile.dart';
import 'chat_service.dart';
import 'connectivity_service.dart';
import 'friend_service.dart';
import 'transport/composite_transport.dart';
import 'transport/lan_transport.dart';
import 'transport/remote_transport.dart';
import 'tts_service.dart';

/// Holds the live app state: the user's profile, UI preferences, the local
/// database and the optional internet backend.
///
/// SINGLE SOURCE OF TRUTH: screens never touch storage, the TTS engine or the
/// backend directly - they call this object, which keeps memory, disk and the
/// live services in sync so a change is visible immediately.
class SessionService {
  SessionService({
    required this.prefs,
    required this.database,
    required this.tts,
    required this.lanTransport,
    required this.transport,
    required this.chatService,
    required this.connectivity,
    required this.backendConfig,
    this.remoteTransport,
    this.backend,
  }) {
    // Read receipts should travel over the internet when it is available.
    chatService.readSyncHook = remoteTransport?.markConversationRead;
  }

  final SharedPreferences prefs;
  final LocalDatabase database;
  final TtsService tts;

  /// Direct device-to-device transport (UDP discovery + TCP chat).
  final LanTransport lanTransport;

  /// The transport the chat layer actually uses: LAN first, internet second.
  final CompositeChatTransport transport;

  /// The internet transport, or null when this build has no backend.
  final RemoteTransport? remoteTransport;

  /// The optional cloud backend, or null when it is not configured.
  final RemoteBackend? backend;

  /// Why the backend is on or off; shown verbatim in Settings.
  final BackendConfig backendConfig;

  final ChatService chatService;
  final ConnectivityService connectivity;

  StreamSubscription<BackendState>? _backendSub;

  /// Friend-code / connection service built on the same storage.
  late final FriendService friendService = FriendService(
    database: database,
    prefs: prefs,
  )
    ..onInviteChanged = _onInviteChanged;

  /// An invite code was issued/refreshed: push it into the LAN announce and the
  /// backend profile so a peer who connected with the typed code can resolve
  /// this device.
  Future<void> _onInviteChanged(String code) async {
    final UserProfile? me = _profile;
    if (me == null) return;
    chatService.setMe(me);
  }

  /// True while the device reports no connectivity (drives the offline UI).
  bool get isOffline => connectivity.isOffline;

  /// True when this build can talk to other people over the internet.
  bool get internetMessagingAvailable => backend != null;

  /// Plain-language backend status for the Settings screen. Deliberately
  /// honest: it reports the real state instead of implying a working backend.
  String get backendStatusLabel {
    final RemoteBackend? api = backend;
    if (api == null) {
      // Configured but never started (bad URL, sign-in refused): say so rather
      // than claiming the build has no backend at all.
      return backendConfig.isConfigured
          ? 'Configured but unavailable'
          : backendConfig.problemMessage;
    }
    switch (api.state) {
      case BackendState.unconfigured:
        return 'Off';
      case BackendState.connecting:
        return 'Connecting...';
      case BackendState.ready:
        return 'Connected';
      case BackendState.error:
        return 'Offline - will retry (${api.lastError ?? 'unreachable'})';
    }
  }

  /// Friend id whose chat screen is currently open, or null. Used so the shell
  /// does not notify twice while the user is already reading that
  /// conversation.
  String? openChatFriendId;

  static const String _kOnboardingSeen = 'onboarding_seen';
  static const String _kTermsAccepted = 'accepted_terms';
  static const String _kTtsEnabled = 'sb_tts_enabled';
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
    // Let every voice setting take effect from the very first announcement.
    tts.enabled = ttsEnabled;
    await _applyVoiceSettings();
    if (_profile != null) {
      chatService.setMe(_profile!);
      chatService.inviteCodeProvider = friendService.storedInviteCode;
    }
    // Adopt the backend identity once it is known, so friends connected over
    // the internet can be addressed.
    _backendSub = backend?.stateChanges.listen((BackendState state) {
      if (state == BackendState.ready) {
        unawaited(_adoptBackendIdentity());
      }
      _profileEvents.add(null);
    });
  }

  /// Stores the backend user id on the local profile the first time it is
  /// available. Existing installs keep their local id (and therefore their
  /// friend list and history); they simply gain an additional online address.
  Future<void> _adoptBackendIdentity() async {
    final RemoteBackend? api = backend;
    final UserProfile? me = _profile;
    if (api == null || me == null) return;
    final String? uid = api.userId;
    if (uid == null || uid.isEmpty || me.remoteId == uid) return;
    await updateProfile(remoteId: uid);
  }

  /// Pushes the stored speech rate/pitch/volume into the TTS engine so the
  /// settings screen takes effect immediately (no restart needed).
  Future<void> _applyVoiceSettings() => tts.configure(
        rate: _ui.ttsRate,
        pitch: _ui.ttsPitch,
        volume: _ui.ttsVolume,
      );

  bool _transportStarted = false;

  /// Starts the LAN transport and, when configured, the internet backend, plus
  /// the connectivity monitor. Safe to call multiple times; fails soft when no
  /// network interface is usable.
  Future<void> startTransport() async {
    await connectivity.start();
    if (_transportStarted || _profile == null) return;
    _transportStarted = true;

    final Map<String, dynamic> identity = chatService.currentIdentity();
    await lanTransport.start(identity);
    chatService.startListening();
    // The internet transport is started last so a failure to sign in never
    // delays the LAN path.
    await remoteTransport?.start(identity);
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
      // If the backend is already signed in, adopt its id straight away.
      remoteId: backend?.userId,
    );
    await database.saveProfile(profile);
    _profile = profile;
    // Hand the new identity to the chat layer: without this, the very first
    // message of a freshly set-up account had no sender and failed.
    chatService.setMe(profile);
    _profileEvents.add(null);
  }

  Future<void> updateProfile({
    String? name,
    UserRole? role,
    String? remoteId,
  }) async {
    if (_profile == null) return;
    final UserProfile updated =
        _profile!.copyWith(name: name, role: role, remoteId: remoteId);
    await database.saveProfile(updated);
    _profile = updated;
    // Keep the chat identity (LAN announcement + backend profile) in sync.
    chatService.setMe(updated);
    _profileEvents.add(null);
  }

  Future<void> updateUiPreferences(AppUiPreferences next) async {
    _ui = next;
    await next.save(prefs);
    // Voice settings must be live: re-apply them on every change.
    await _applyVoiceSettings();
  }

  // ---------------- Notification / vibration / voice toggles ----------------

  /// Speaks confirmations and received messages (blind mode).
  bool get ttsEnabled => prefs.getBool(_kTtsEnabled) ?? true;

  /// Shows new-message banners in deaf mode.
  bool get notificationsEnabled =>
      prefs.getBool(_kNotificationsEnabled) ?? true;

  /// Vibrates on incoming messages in deaf mode.
  bool get vibrationEnabled => prefs.getBool(_kVibrationEnabled) ?? true;

  /// The effective decision for one incoming message: the Alerts switch is the
  /// feature, the Accessibility switch is the device-wide master. Both must be
  /// on, so "Haptics" in Accessibility really does turn vibration off instead
  /// of being a switch that changes nothing.
  bool get shouldVibrateOnIncoming => vibrationEnabled && ui.hapticsEnabled;

  Future<void> setTtsEnabled(bool value) async {
    await prefs.setBool(_kTtsEnabled, value);
    tts.enabled = value;
  }

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

  // ---------------- Friends ----------------

  /// Removes a friend everywhere: locally (history + blocklist, so their old
  /// code cannot silently re-add them) and on the backend, so they can no
  /// longer read or send anything over the internet.
  ///
  /// The backend call is best effort: the local removal must always succeed,
  /// even offline.
  Future<void> removeFriend(Friend friend) async {
    await database.removeFriend(friend.id);
    await remoteTransport?.revoke(friend.id);
    _profileEvents.add(null);
  }

  // ---------------- Privacy ----------------

  /// Wipes all conversations. Friends are kept; codes of removed friends
  /// stay blocked until both users re-confirm a connection.
  Future<void> deleteAllConversations() =>
      database.deleteAllConversations();

  // ---------------- Testing helper ----------------

  /// Adds the built-in TEST/SAMPLE friend (no network, no real person) so the
  /// whole chat + translation flow can be tried on one device.
  Future<Friend> addSampleFriend() async {
    final UserProfile me = _profile!;
    final Friend friend = await chatService.sampleFriend.ensureInstalled(me);
    // The greeting lands in the unread list: nudge the shell to refresh it.
    _profileEvents.add(null);
    return friend;
  }

  String _generateId(String prefix) {
    final DateTime now = DateTime.now();
    final int millis = now.millisecondsSinceEpoch;
    final int random = DateTime.now().microsecondsSinceEpoch % 100000;
    return '$prefix-$millis-$random';
  }

  Future<void> dispose() async {
    await _backendSub?.cancel();
    _profileEvents.close();
    chatService.dispose();
    await transport.dispose();
    lanTransport.dispose();
    await backend?.dispose();
  }
}
