import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartbridgeapp/models/emotion.dart';
import 'package:smartbridgeapp/widgets/accessibility.dart';
import 'package:smartbridgeapp/widgets/emotion_badge.dart';

/// Regression tests for the accessibility/UI defects found in the final audit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  group('Emotion.fromName never invents a feeling', () {
    test('known names resolve', () {
      expect(Emotion.fromName('happy'), Emotion.happy);
      expect(Emotion.fromName('sad'), Emotion.sad);
      expect(Emotion.fromName('angry'), Emotion.angry);
      expect(Emotion.fromName('shy'), Emotion.shy);
    });

    test('an absent emotion stays absent', () {
      expect(Emotion.fromName(null), isNull);
    });

    test('an unknown/corrupted emotion is NOT mapped to Happy', () {
      // The old implementation fell back to Emotion.happy, which would make a
      // blind recipient hear "Happy." for a feeling nobody chose.
      expect(Emotion.fromName('ecstatic'), isNull);
      expect(Emotion.fromName(''), isNull);
      expect(Emotion.fromName('HAPPY'), isNull, reason: 'case sensitive');
      expect(Emotion.fromName('null'), isNull);
    });
  });

  // ==========================================================================
  group('Emotion colours are readable on the active theme', () {
    test('light mode keeps the designed palette', () {
      for (final Emotion emotion in Emotion.values) {
        expect(emotion.colorFor(Brightness.light), emotion.color);
      }
    });

    test('dark mode lifts every emotion so the label stays legible', () {
      for (final Emotion emotion in Emotion.values) {
        final Color dark = emotion.colorFor(Brightness.dark);
        final HSLColor hsl = HSLColor.fromColor(dark);
        // The mid-tone originals only reach ~2.5:1 on a dark surface.
        expect(
          hsl.lightness,
          greaterThan(HSLColor.fromColor(emotion.color).lightness),
          reason: '${emotion.label} should be brighter on a dark theme',
        );
        expect(hsl.lightness, greaterThan(0.5));
      }
    });
  });

  // ==========================================================================
  group('BigButton', () {
    Widget wrap(Widget child, {double textScale = 1.0, bool dark = false}) {
      return MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (BuildContext context, Widget? inner) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: Scaffold(body: ListView(children: <Widget>[child])),
      );
    }

    double measuredHeight(WidgetTester tester) =>
        tester.getSize(find.byType(BigButton)).height;

    Future<void> pumpAt(WidgetTester tester, double scale) async {
      await tester.pumpWidget(wrap(
        BigButton(
          label: 'Send a voice message',
          icon: Icons.mic_rounded,
          subtext: 'Speak, check the simplified text, send',
          onPressed: () {},
        ),
        textScale: scale,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('meets the 68dp touch-target minimum at the default size',
        (WidgetTester tester) async {
      await pumpAt(tester, 1.0);
      expect(tester.takeException(), isNull);
      expect(measuredHeight(tester), 68);
    });

    testWidgets('can never truncate its label (no ellipsis, no maxLines)',
        (WidgetTester tester) async {
      // Regression: both lines used TextOverflow.ellipsis inside a fixed 68dp
      // box, so a long label was silently cut to "Speak, check the simplifie…"
      // for anyone reading the screen visually. Wrapping is now allowed, which
      // is what makes truncation structurally impossible.
      await pumpAt(tester, 1.4);
      expect(tester.takeException(), isNull);

      final Iterable<Text> lines = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(BigButton),
          matching: find.byType(Text),
        ),
      );
      expect(lines, hasLength(2), reason: 'label + subtext');
      for (final Text line in lines) {
        expect(line.overflow, isNot(TextOverflow.ellipsis));
        expect(line.maxLines, isNull);
      }

      // Both strings are present and laid out, not clipped away.
      expect(find.text('Send a voice message'), findsOneWidget);
      expect(find.text('Speak, check the simplified text, send'),
          findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(
          find.text('Speak, check the simplified text, send'),
        ),
        isNotNull,
      );
    });

    testWidgets('survives an extreme font scale without breaking layout',
        (WidgetTester tester) async {
      // Well past what the settings slider allows, so the button can never
      // overflow if the cap is ever raised.
      await pumpAt(tester, 2.5);
      expect(tester.takeException(), isNull,
          reason: 'a RenderFlex overflow would be reported here');
      expect(measuredHeight(tester), greaterThan(68));
    });

    testWidgets('exposes ONE labelled semantics node, including the subtext',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(
        BigButton(
          label: 'Send a voice message',
          icon: Icons.mic_rounded,
          subtext: 'Speak, check the simplified text, send',
          onPressed: () {},
        ),
      ));
      await tester.pumpAndSettle();

      final SemanticsData data =
          tester.getSemantics(find.byType(BigButton)).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.label, contains('Send a voice message'));
      // The hint is part of the same announcement, not a separate node the
      // screen reader reads as a stray fragment.
      expect(data.label, contains('Speak, check the simplified text, send'));

      handle.dispose();
    });

    testWidgets('remains ACTIVATABLE by a screen reader', (WidgetTester tester) async {
      // Regression guard: `excludeSemantics: true` hides the button's own
      // semantics, so the tap action must be re-published on the wrapper.
      // Without it a TalkBack user could focus the control but not press it.
      final SemanticsHandle handle = tester.ensureSemantics();
      int taps = 0;
      await tester.pumpWidget(wrap(
        BigButton(
          label: 'Settings',
          icon: Icons.settings_rounded,
          onPressed: () => taps++,
        ),
      ));
      await tester.pumpAndSettle();

      final SemanticsData data =
          tester.getSemantics(find.byType(BigButton)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue);

      // Activate it the way a screen reader would, not with a physical tap.
      tester.semantics.tap(find.semantics.byLabel('Settings'));
      await tester.pumpAndSettle();

      expect(taps, 1, reason: 'the semantic tap must reach onPressed');
      handle.dispose();
    });

    testWidgets('a disabled button is reported as disabled, not pressable',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(wrap(
        BigButton(label: 'Send message', icon: Icons.send, onPressed: null),
      ));
      await tester.pumpAndSettle();

      final SemanticsData data =
          tester.getSemantics(find.byType(BigButton)).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });
  });

  // ==========================================================================
  group('EmotionBadge', () {
    testWidgets('uses the theme-aware colour and one clean announcement',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();

      Color renderedColour() => tester
          .widget<Text>(find.descendant(
            of: find.byType(EmotionBadge),
            matching: find.text('Happy'),
          ))
          .style!
          .color!;

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: EmotionBadge(emotion: Emotion.happy)),
      ));
      await tester.pumpAndSettle();
      final Color light = renderedColour();
      expect(light, Emotion.happy.color);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: EmotionBadge(emotion: Emotion.happy)),
      ));
      await tester.pumpAndSettle();
      final Color dark = renderedColour();

      expect(dark, isNot(light));
      expect(
        HSLColor.fromColor(dark).lightness,
        greaterThan(HSLColor.fromColor(light).lightness),
      );

      // The badge announces itself once: "Emotion Happy", not "Happy Happy".
      final SemanticsData data =
          tester.getSemantics(find.byType(EmotionBadge)).getSemanticsData();
      expect(data.label, 'Emotion Happy');

      handle.dispose();
    });
  });
}
