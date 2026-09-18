import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbridgeapp/models/ui_preferences.dart';
import 'package:smartbridgeapp/widgets/app_theme.dart';

/// Regression tests for "settings must update immediately and persist".
///
/// The reported bug: changing the font size saved the value but the UI only
/// picked it up after a restart, because the theme layer (MyApp) was never
/// told about the change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // No network in tests: never try to download fonts.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('UI preference persistence', () {
    test('font size survives a save/load round trip', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await const AppUiPreferences()
          .copyWith(textScale: 1.25, highContrast: true)
          .save(prefs);

      // Simulates restarting the app: read the values back from storage.
      final AppUiPreferences reloaded =
          AppUiPreferences.fromSharedPreferences(prefs);

      expect(reloaded.textScale, 1.25);
      expect(reloaded.highContrast, isTrue);
    });

    test('out-of-range font sizes are clamped on load', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'pref_text_scale': 99.0,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      expect(AppUiPreferences.fromSharedPreferences(prefs).textScale, 1.4);
    });
  });

  group('Theme layer reacts instantly', () {
    testWidgets('changing font size rescales text without a restart',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late double observedScale;

      await tester.pumpWidget(MyApp(
        homeBuilder: (
          BuildContext context,
          AppUiPreferences prefs,
          ValueChanged<AppUiPreferences> onChanged,
        ) {
          return Scaffold(
            body: Builder(
              builder: (BuildContext inner) {
                // Read from a descendant context so the MaterialApp builder's
                // textScaler override is visible, exactly like the real screens.
                observedScale = MediaQuery.textScalerOf(inner).scale(10);
                return Column(
                  children: <Widget>[
                    Text('scale ${observedScale.toStringAsFixed(1)}'),
                    ElevatedButton(
                      onPressed: () =>
                          onChanged(prefs.copyWith(textScale: 1.4)),
                      child: const Text('bigger'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ));
      await tester.pumpAndSettle();

      expect(observedScale, 10.0);

      await tester.tap(find.text('bigger'));
      await tester.pumpAndSettle();

      // Immediate: the same frame tree is already scaled up.
      expect(observedScale, 14.0);
      expect(find.text('scale 14.0'), findsOneWidget);

      // Persisted for the next launch.
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('pref_text_scale'), 1.4);
    });

    testWidgets('high contrast switch rebuilds the theme immediately',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late bool sawHighContrast;

      await tester.pumpWidget(MyApp(
        homeBuilder: (
          BuildContext context,
          AppUiPreferences prefs,
          ValueChanged<AppUiPreferences> onChanged,
        ) {
          return Scaffold(
            body: Builder(
              builder: (BuildContext inner) {
                sawHighContrast = prefs.highContrast;
                return ElevatedButton(
                  onPressed: () =>
                      onChanged(prefs.copyWith(highContrast: true)),
                  child: const Text('contrast'),
                );
              },
            ),
          );
        },
      ));
      await tester.pumpAndSettle();
      expect(sawHighContrast, isFalse);

      await tester.tap(find.text('contrast'));
      await tester.pumpAndSettle();

      expect(sawHighContrast, isTrue);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pref_high_contrast'), isTrue);
    });

    testWidgets(
        'high contrast actually changes the RENDERED colours, not just storage',
        (WidgetTester tester) async {
      // Regression: MyApp built a custom colour scheme (including the
      // high-contrast overrides) and then passed a brand-new
      // ColorScheme.fromSeed() to ThemeData, so the switch silently did
      // nothing. Asserting the stored preference was not enough - the test
      // above passed while the feature was broken.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late Color onSurface;

      await tester.pumpWidget(MyApp(
        homeBuilder: (
          BuildContext context,
          AppUiPreferences prefs,
          ValueChanged<AppUiPreferences> onChanged,
        ) {
          return Scaffold(
            body: Builder(
              builder: (BuildContext inner) {
                onSurface = Theme.of(inner).colorScheme.onSurface;
                return ElevatedButton(
                  onPressed: () =>
                      onChanged(prefs.copyWith(highContrast: true)),
                  child: const Text('contrast'),
                );
              },
            ),
          );
        },
      ));
      await tester.pumpAndSettle();

      final Color normal = onSurface;

      await tester.tap(find.text('contrast'));
      await tester.pumpAndSettle();

      // Light-mode high contrast forces pure black text on pure white.
      expect(onSurface, Colors.black);
      expect(normal, isNot(onSurface));
    });

    testWidgets('the theme mode switch re-themes on the same frame',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late Brightness brightness;

      await tester.pumpWidget(MyApp(
        homeBuilder: (
          BuildContext context,
          AppUiPreferences prefs,
          ValueChanged<AppUiPreferences> onChanged,
        ) {
          return Scaffold(
            body: Builder(
              builder: (BuildContext inner) {
                brightness = Theme.of(inner).brightness;
                return ElevatedButton(
                  onPressed: () => onChanged(
                    prefs.copyWith(themeMode: ThemeMode.light),
                  ),
                  child: const Text('light'),
                );
              },
            ),
          );
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('light'));
      await tester.pumpAndSettle();

      expect(brightness, Brightness.light);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('pref_theme_mode'), 'light');
    });
  });

  group('Reduce motion', () {
    testWidgets('removes route animation and tells widgets to stop animating',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      late bool disableAnimations;
      late PageTransitionsBuilder builder;

      await tester.pumpWidget(MyApp(
        homeBuilder: (
          BuildContext context,
          AppUiPreferences prefs,
          ValueChanged<AppUiPreferences> onChanged,
        ) {
          return Scaffold(
            body: Builder(
              builder: (BuildContext inner) {
                disableAnimations = MediaQuery.disableAnimationsOf(inner);
                final ThemeData theme = Theme.of(inner);
                builder = theme.pageTransitionsTheme.builders[TargetPlatform
                        .android] ??
                    const ZoomPageTransitionsBuilder();
                return ElevatedButton(
                  onPressed: () => onChanged(prefs.copyWith(reduceMotion: true)),
                  child: const Text('calm'),
                );
              },
            ),
          );
        },
      ));
      await tester.pumpAndSettle();

      expect(disableAnimations, isFalse);
      expect(builder, isA<ZoomPageTransitionsBuilder>());

      await tester.tap(find.text('calm'));
      await tester.pumpAndSettle();

      // The switch used to be stored and then ignored by the messaging app.
      expect(disableAnimations, isTrue);
      expect(builder, isNot(isA<ZoomPageTransitionsBuilder>()));
    });
  });
}
