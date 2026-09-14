import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database/local_database.dart';
import 'models/ui_preferences.dart';
import 'screens/app_shell.dart';
import 'screens/legacy/onboarding_screen.dart';
import 'screens/setup_screen.dart';
import 'services/chat_service.dart';
import 'services/connectivity_service.dart';
import 'services/session_service.dart';
import 'services/transport/lan_transport.dart';
import 'services/tts_service.dart';
import 'widgets/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

/// Creates services, waits for storage, then hands control to the themed app.
class Bootstrap extends StatelessWidget {
  const Bootstrap({super.key});

  static final TtsService _tts = TtsService();
  static final LanTransport _transport = LanTransport();
  static final ConnectivityService _connectivity = ConnectivityService();

  static Future<SessionService> _createSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LocalDatabase database = LocalDatabase(prefs);
    final ChatService chatService = ChatService(
      database: database,
      transport: _transport,
      tts: _tts,
    );
    final SessionService session = SessionService(
      prefs: prefs,
      database: database,
      tts: _tts,
      transport: _transport,
      chatService: chatService,
      connectivity: _connectivity,
    );
    await session.load();
    return session;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SessionService>(
      future: _createSession(),
      builder: (BuildContext context, AsyncSnapshot<SessionService> snapshot) {
        if (!snapshot.hasData) {
          // Minimal splash while storage initialises.
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
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
    return AppRoot(session: session);
  }
}
