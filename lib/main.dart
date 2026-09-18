import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend/backend_config.dart';
import 'backend/remote_backend.dart';
import 'backend/supabase_remote_backend.dart';
import 'database/local_database.dart';
import 'models/ui_preferences.dart';
import 'screens/app_shell.dart';
import 'screens/legacy/onboarding_screen.dart';
import 'screens/setup_screen.dart';
import 'services/chat_service.dart';
import 'services/connectivity_service.dart';
import 'services/session_service.dart';
import 'services/transport/composite_transport.dart';
import 'services/transport/lan_transport.dart';
import 'services/transport/remote_transport.dart';
import 'services/tts_service.dart';
import 'widgets/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

/// Creates services, waits for storage, then hands control to the themed app.
///
/// Stateful so the (async) session is created exactly once: a StatelessWidget
/// would re-run the future on every rebuild, silently re-initialising the
/// backend and every transport.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late final Future<SessionService> _session = _createSession();

  final TtsService _tts = TtsService();
  final ConnectivityService _connectivity = ConnectivityService();

  /// Builds the internet backend when credentials are present, otherwise
  /// returns null and the app runs exactly as it does without a backend.
  ///
  /// A misconfiguration (bad URL, revoked key, anonymous sign-in disabled) can
  /// never break startup: the failure is caught, the backend stays null and
  /// the reason is shown in Settings.
  Future<RemoteBackend?> _createBackend(
    BackendConfig config,
    LocalDatabase database,
  ) async {
    if (!config.isConfigured) return null;
    try {
      // `publishableKey` accepts both the legacy anon JWT and the newer
      // `sb_publishable_...` format. Never a secret/service-role key:
      // BackendConfig refuses to configure the app if one is supplied.
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.anonKey,
      );
      return SupabaseRemoteBackend(
        client: Supabase.instance.client,
        friendRemoteIds: () => database
            .loadFriends()
            .map((friend) => friend.remoteId)
            .whereType<String>()
            .toSet(),
      );
    } catch (error) {
      debugPrint('Backend unavailable, continuing offline: $error');
      return null;
    }
  }

  Future<SessionService> _createSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalDatabase database = LocalDatabase(prefs);
    final BackendConfig config = BackendConfig.fromEnvironment();

    final RemoteBackend? backend = await _createBackend(config, database);
    final RemoteTransport? remoteTransport = backend == null
        ? null
        : RemoteTransport(backend: backend, database: database);

    final LanTransport lanTransport = LanTransport();
    final CompositeChatTransport transport = CompositeChatTransport(
      <ChatTransport>[
        // LAN first: two phones on the same Wi-Fi stay direct - faster,
        // private and free. The internet is the fallback.
        lanTransport,
        ?remoteTransport,
      ],
    );

    final ChatService chatService = ChatService(
      database: database,
      transport: transport,
      tts: _tts,
    );

    final SessionService session = SessionService(
      prefs: prefs,
      database: database,
      tts: _tts,
      lanTransport: lanTransport,
      transport: transport,
      remoteTransport: remoteTransport,
      backend: backend,
      backendConfig: config,
      chatService: chatService,
      connectivity: _connectivity,
    );
    await session.load();
    return session;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionService>(
      future: _session,
      builder: (BuildContext context, AsyncSnapshot<SessionService> snapshot) {
        if (!snapshot.hasData) {
          // Minimal splash while storage initialises.
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'Loading SmartBridge Messages',
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),
          );
        }

        final SessionService session = snapshot.data!;
        return MyApp(
          homeBuilder: (BuildContext context,
              AppUiPreferences prefs,
              ValueChanged<AppUiPreferences> onChanged) {
            return MessagingAppGate(
              session: session,
              prefs: prefs,
              onPreferencesChanged: onChanged,
            );
          },
        );
      },
    );
  }
}

/// Routes between onboarding, setup and the main app.
class MessagingAppGate extends StatefulWidget {
  const MessagingAppGate({
    super.key,
    required this.session,
    required this.prefs,
    required this.onPreferencesChanged,
  });

  final SessionService session;
  final AppUiPreferences prefs;
  final ValueChanged<AppUiPreferences> onPreferencesChanged;

  @override
  State<MessagingAppGate> createState() => _MessagingAppGateState();
}

class _MessagingAppGateState extends State<MessagingAppGate> {
  @override
  void initState() {
    super.initState();
    widget.session.profileEvents.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final SessionService session = widget.session;

    // 1. First launch: original onboarding + terms flow.
    if (!session.hasSeenOnboarding || !session.hasAcceptedTerms) {
      return OnboardingGate(onAccepted: () async {
        await session.acceptOnboarding();
        if (context.mounted) setState(() {});
      });
    }

    // 2. No profile yet: role setup (I AM BLIND / I AM DEAF).
    if (!session.hasProfile) {
      return SetupScreen(
        session: session,
        onSetupComplete: () {
          if (context.mounted) setState(() {});
        },
      );
    }

    // 3. Main messaging app.
    //    [prefs] and [onPreferencesChanged] belong to MyApp (the theme layer:
    //    text scale, theme mode, high contrast). They are forwarded all the way
    //    down so a settings change is visible instantly, not only after a
    //    restart.
    return AppRoot(
      session: session,
      prefs: widget.prefs,
      onPreferencesChanged: widget.onPreferencesChanged,
    );
  }
}
