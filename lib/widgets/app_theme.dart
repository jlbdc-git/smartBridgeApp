import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ui_preferences.dart';

/// Root app widget + adaptive theme (extracted from the original main.dart).
/// The home is provided by [homeBuilder] so the messaging entry point lives
/// in main.dart while theming stays here.
class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.homeBuilder});

  final Widget Function(
    BuildContext context,
    AppUiPreferences prefs,
    ValueChanged<AppUiPreferences> onChanged,
  ) homeBuilder;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppUiPreferences _prefs = const AppUiPreferences();
  bool _ready = false;

  static const Color _seedColor = Color(0xFF0A7A75);

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _prefs = AppUiPreferences.fromSharedPreferences(prefs);
      _ready = true;
    });
  }

  Future<void> _updatePreferences(AppUiPreferences next) async {
    setState(() => _prefs = next);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await next.save(prefs);
  }

  ThemeData _buildTheme(Brightness brightness) {
    ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );

    scheme = scheme.copyWith(
      primary: brightness == Brightness.dark
          ? const Color(0xFF6AF6ED)
          : const Color(0xFF006F69),
      onPrimary: brightness == Brightness.dark
          ? const Color(0xFF003534)
          : Colors.white,
      primaryContainer: brightness == Brightness.dark
          ? const Color(0xFF1C5D63)
          : const Color(0xFFA7F0EB),
      onPrimaryContainer: brightness == Brightness.dark
          ? const Color(0xFFE6FFFF)
          : const Color(0xFF003735),
      surface: brightness == Brightness.dark
          ? const Color(0xFF101A1F)
          : const Color(0xFFF8FBFC),
      onSurface: brightness == Brightness.dark
          ? const Color(0xFFF5FDFF)
          : const Color(0xFF0E2325),
      surfaceContainer: brightness == Brightness.dark
          ? const Color(0xFF1B2A31)
          : const Color(0xFFEAF4F6),
      surfaceContainerHighest: brightness == Brightness.dark
          ? const Color(0xFF263942)
          : const Color(0xFFDDECEF),
      onSurfaceVariant: brightness == Brightness.dark
          ? const Color(0xFFE1EDF0)
          : const Color(0xFF315258),
      outline: brightness == Brightness.dark
          ? const Color(0xFF9DB8BE)
          : const Color(0xFF5B7B81),
      outlineVariant: brightness == Brightness.dark
          ? const Color(0xFF4C6871)
          : const Color(0xFFB1C7CB),
    );

    if (_prefs.highContrast) {
      scheme = scheme.copyWith(
        primary: brightness == Brightness.dark
            ? const Color(0xFF64FFF6)
            : const Color(0xFF005A56),
        onPrimary: brightness == Brightness.dark
            ? const Color(0xFF002221)
            : Colors.white,
        surface: brightness == Brightness.dark
            ? const Color(0xFF0C1216)
            : Colors.white,
        onSurface: brightness == Brightness.dark ? Colors.white : Colors.black,
      );
    }

    final TextTheme appTextTheme = GoogleFonts.manropeTextTheme(
      ThemeData(useMaterial3: true, brightness: brightness).textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    // Minimalistic, high-contrast theme: cleaner surfaces, larger tappables,
    // subtle rounded corners, and reduced chrome to avoid a technical look.
    //
    // NOTE: everything below reads from [scheme]. An earlier version built this
    // scheme (including the high-contrast overrides) and then passed a fresh
    // `ColorScheme.fromSeed(...)` to ThemeData, which silently threw all of it
    // away - the high-contrast switch had no visible effect at all.
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: appTextTheme,
      scaffoldBackgroundColor: scheme.surface,
      // Reduce motion is applied to navigation too, not just to widgets that
      // happen to check MediaQuery.disableAnimations.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          for (final TargetPlatform platform in TargetPlatform.values)
            platform: _prefs.reduceMotion
                ? const _NoAnimationPageTransitionsBuilder()
                : const ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: appTextTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        toolbarHeight: 64,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: brightness == Brightness.dark ? const Color(0xFF0F1112) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          // scheme.onPrimary, not a hard-coded white: in dark mode the primary
          // colour is light cyan, where white text would be unreadable.
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: appTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.dark ? const Color(0xFF121315) : const Color(0xFFF3F4F6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 16.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SmartBridge',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _prefs.themeMode,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(_prefs.textScale),
            // Honours the "Reduce motion" switch for every widget that checks
            // it, without touching MaterialApp-level transitions.
            disableAnimations: _prefs.reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _ready
          ? widget.homeBuilder(context, _prefs, _updatePreferences)
          : const _LoadingScaffold(label: 'Loading SmartBridge...'),
    );
  }
}


/// Navigation transition with no animation, used when "Reduce motion" is on.
/// Chosen over simply shortening the duration because a zero-length animation
/// still rebuilds every frame of the route transition.
class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Simple loading splash (kept from the original main.dart).
class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Text(label),
          ],
        ),
      ),
    );
  }
}
