import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbridgeapp/main.dart' as app;
import 'package:smartbridgeapp/models/emotion.dart';
import 'package:smartbridgeapp/models/user_profile.dart';
import 'package:smartbridgeapp/screens/blind_translator_screen.dart';
import 'package:smartbridgeapp/screens/chat_screen.dart';
import 'package:smartbridgeapp/screens/deaf_translator_screen.dart';
import 'package:smartbridgeapp/screens/home_screen.dart';
import 'package:smartbridgeapp/screens/settings_screen.dart';
import 'package:smartbridgeapp/screens/setup_screen.dart';
import 'package:smartbridgeapp/services/sample_friend.dart';
import 'package:smartbridgeapp/widgets/accessibility.dart';
import 'package:smartbridgeapp/widgets/message_bubble.dart';

/// On-device end-to-end test of the real app, with every plugin active.
///
///   flutter test integration_test/app_flow_test.dart -d `device-id`
///
/// Covers set-up for a deaf user, the built-in sample friend, sending and
/// receiving messages, the deaf translator (grammar improvement + manually
/// chosen emotion), the blind-mode UI, and a live text-size change.
///
/// On a real device the Android IME animates outside Flutter, so a tap can
/// land before the layout settles. Every interaction below therefore retries
/// until it has a visible effect.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  /// Pumps frames until [finder] matches.
  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out waiting for: $finder');
  }

  /// Closes the soft keyboard so the layout stops moving before a tap.
  Future<void> dismissKeyboard(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 800));
  }

  /// Scrollable that holds [within]'s content (the list itself, not a field).
  Finder scrollableInside(Finder within) =>
      find.descendant(of: within, matching: find.byType(Scrollable)).first;

  /// Scrolls [finder] into view without tapping it. [scrollDelta] is negative
  /// to search upwards.
  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    required Finder within,
    double scrollDelta = 400,
  }) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        scrollDelta,
        scrollable: scrollableInside(within),
        maxScrolls: 40,
      );
      await settle(tester);
    }
    await tester.ensureVisible(finder);
    await settle(tester);
  }

  /// Brings [finder] into view, then taps it repeatedly until [done] holds.
  Future<void> tapUntil(
    WidgetTester tester,
    Finder finder,
    bool Function() done, {
    Finder? within,
    double scrollDelta = 400,
    int attempts = 6,
    String? reason,
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      if (done()) return;
      await reveal(
        tester,
        finder,
        within: within ?? find.byType(MaterialApp),
        scrollDelta: scrollDelta,
      );
      await tester.tap(finder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 700));
      await settle(tester);
    }
    if (!done()) {
      fail(reason ?? 'Tapping $finder had no visible effect');
    }
  }

  /// Drags [finder] until [done] holds.
  Future<void> dragUntil(
    WidgetTester tester,
    Finder finder,
    Offset delta,
    bool Function() done, {
    int attempts = 5,
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      if (done()) return;
      await tester.ensureVisible(finder);
      await settle(tester);
      await tester.drag(finder, delta);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
    }
    if (!done()) fail('Dragging $finder had no effect');
  }

  /// Message bubbles in tree order - assertions read the real message model.
  List<MessageBubble> bubbles(WidgetTester tester) =>
      tester.widgetList<MessageBubble>(find.byType(MessageBubble)).toList();

  /// The stored conversation for the sample friend, straight from disk.
  List<Map<String, dynamic>> storedConversation(SharedPreferences prefs) {
    final String? raw =
        prefs.getString('sb_msgs_${SampleFriendService.friendId}');
    if (raw == null) return <Map<String, dynamic>>[];
    return (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  bool onScreen(Finder finder) => finder.evaluate().isNotEmpty;

  testWidgets('a deaf and a blind user hold one shared conversation',
      (WidgetTester tester) async {
    // Clean device, already past onboarding: this test targets the messaging
    // flows themselves.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('onboarding_seen', true);
    await prefs.setBool('accepted_terms', true);

    app.main();
    await tester.pump();

    // ---------------- Welcome / Setup ----------------
    await pumpUntil(tester, find.byType(SetupScreen));
    expect(find.text('I AM BLIND'), findsOneWidget);
    expect(find.text('I AM DEAF'), findsOneWidget);

    await tapUntil(
      tester,
      find.text('I AM DEAF'),
      () => onScreen(find.byIcon(Icons.check_circle)),
      reason: 'the deaf role should be selectable',
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(SetupScreen),
        matching: find.byType(TextField),
      ),
      'Bea',
    );
    await settle(tester);
    await dismissKeyboard(tester);

    await tapUntil(
      tester,
      find.widgetWithText(BigButton, 'Start'),
      () => !onScreen(find.byType(SetupScreen)),
      within: find.byType(SetupScreen),
      reason: 'Start should finish setup',
    );

    // ---------------- Deaf home: add the TEST friend ----------------
    await pumpUntil(tester, find.text('Add sample friend (TEST)'));
    await tapUntil(
      tester,
      find.text('Add sample friend (TEST)'),
      () => onScreen(find.textContaining(SampleFriendService.displayName)),
      reason: 'the sample friend should be added',
    );

    // The test contact is unmistakably labelled...
    expect(find.textContaining('SAMPLE'), findsWidgets);
    // ...and its greeting arrives unread, shown as a badge on the home screen.
    expect(find.text('1 new message'), findsOneWidget);

    final List<Map<String, dynamic>> seeded = storedConversation(prefs);
    expect(seeded, hasLength(1));
    expect(seeded.first['senderId'], SampleFriendService.friendId);
    expect(seeded.first['readByReceiver'], isFalse);

    // ---------------- Open the conversation ----------------
    await tapUntil(
      tester,
      find.textContaining(SampleFriendService.displayName).first,
      () => onScreen(find.byType(MessageBubble)),
      reason: 'the conversation should open',
    );
    // Opening a conversation marks it read, and that is persisted.
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      storedConversation(prefs).first['readByReceiver'],
      isTrue,
      reason: 'opening the chat should mark the greeting as read',
    );

    final List<MessageBubble> initial = bubbles(tester);
    expect(initial, isNotEmpty);
    // The seeded greeting comes from the blind partner, so it carries no
    // emotion (only deaf senders attach one).
    expect(initial.first.message.senderId, SampleFriendService.friendId);
    expect(initial.first.message.emotion, isNull);

    // ---------------- Deaf translator: improve + emotion ----------------
    await tapUntil(
      tester,
      find.byTooltip('Write with translator'),
      () => onScreen(find.byType(DeafTranslatorScreen)),
      reason: 'the deaf translator should open',
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(DeafTranslatorScreen),
        matching: find.byType(TextField),
      ),
      'you free tomorrow? i want go mall with you',
    );
    await settle(tester);
    await dismissKeyboard(tester);

    // Acceptance B, on the real screen: broken input -> natural English.
    expect(
      find.textContaining('I want to go to the mall with you'),
      findsWidgets,
      reason: 'the deaf translator should improve the typed sentence',
    );

    final Finder happyChip = find.widgetWithText(ChoiceChip, 'HAPPY');
    await tapUntil(
      tester,
      happyChip,
      () => tester.widget<ChoiceChip>(happyChip).selected,
      within: find.byType(DeafTranslatorScreen),
      reason: 'the emotion chip should be selectable',
    );

    await tapUntil(
      tester,
      find.widgetWithText(BigButton, 'Send message'),
      () => !onScreen(find.byType(DeafTranslatorScreen)),
      within: find.byType(DeafTranslatorScreen),
      reason: 'sending should close the translator',
    );

    // ---------------- The message really lands in the conversation --------
    await pumpUntil(tester, find.byType(MessageBubble));

    List<MessageBubble> fromMe() => bubbles(tester)
        .where(
          (MessageBubble b) => b.message.senderId != SampleFriendService.friendId,
        )
        .toList();
    int fromSample() => bubbles(tester)
        .where((MessageBubble b) => b.message.senderId == SampleFriendService.friendId)
        .length;

    final DateTime sendDeadline =
        DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(sendDeadline) && fromMe().isEmpty) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(fromMe(), hasLength(1), reason: 'one tap sends exactly one message');
    expect(fromMe().single.message.translatedText, contains('mall'));
    // The emotion is exactly the one the user picked - never inferred.
    expect(fromMe().single.message.emotion, Emotion.happy);

    // ---------------- The sample friend answers ----------------
    final DateTime replyDeadline =
        DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(replyDeadline) && fromSample() < 2) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(
      fromSample(),
      greaterThanOrEqualTo(2),
      reason: 'the sample friend should answer a sent message',
    );
    final MessageBubble reply = bubbles(tester).lastWhere(
      (MessageBubble b) => b.message.senderId == SampleFriendService.friendId,
    );
    expect(reply.message.displayText.trim(), isNotEmpty);
    // A blind partner never attaches an emotion (nothing invented).
    expect(reply.message.emotion, isNull);

    // ---------------- Settings: text size applies instantly ----------------
    await tester.pageBack();
    await settle(tester);
    await tapUntil(
      tester,
      find.byTooltip('Settings'),
      () => onScreen(find.byType(AppSettingsScreen)),
      reason: 'the settings tab should open',
    );

    final Finder fontLabel = find.descendant(
      of: find.byType(AppSettingsScreen),
      matching: find.text('Font size'),
    );
    await reveal(tester, fontLabel, within: find.byType(AppSettingsScreen));

    double textScaleNow() =>
        MediaQuery.textScalerOf(tester.element(fontLabel)).scale(10);
    final double heightBefore = tester.getSize(fontLabel).height;

    expect(textScaleNow(), 10.0, reason: 'default text scale');

    final Finder fontSlider = find.descendant(
      of: find.ancestor(of: fontLabel, matching: find.byType(Column)).first,
      matching: find.byType(Slider),
    );
    await dragUntil(
      tester,
      fontSlider,
      const Offset(600, 0),
      () => (prefs.getDouble('pref_text_scale') ?? 1.0) > 1.0,
    );

    // IMMEDIATE: no restart, no navigation - the very next frame is scaled.
    final double persisted = prefs.getDouble('pref_text_scale')!;
    expect(
      textScaleNow(),
      closeTo(persisted * 10, 0.001),
      reason: 'the UI must apply the new text size without a restart',
    );
    expect(
      tester.getSize(fontLabel).height,
      greaterThan(heightBefore),
      reason: 'text must actually render larger',
    );

    // High contrast is also live.
    await tapUntil(
      tester,
      find.widgetWithText(SwitchListTile, 'High contrast'),
      () => prefs.getBool('pref_high_contrast') ?? false,
      within: find.byType(AppSettingsScreen),
      reason: 'high contrast should persist immediately',
    );

    // ---------------- Switch role to BLIND ----------------
    await tapUntil(
      tester,
      find.descendant(
        of: find.byType(AppSettingsScreen),
        matching: find.text('Blind'),
      ),
      () =>
          UserProfile.tryDecode(prefs.getString('sb_profile'))?.role ==
          UserRole.blind,
      within: find.byType(AppSettingsScreen),
      // Profile sits above the Accessibility section: search upwards.
      scrollDelta: -400,
      reason: 'the role change should be saved',
    );
    await tapUntil(
      tester,
      find.byTooltip('Back to home'),
      () => onScreen(find.byType(HomeScreen)),
      reason: 'settings should offer a way back to the home screen',
    );

    // The shell re-rendered as the blind, voice-first home straight away.
    await pumpUntil(tester, find.text('Send a voice message'));

    // Blind reading: open the last conversation, check the TTS controls.
    await tapUntil(
      tester,
      find.descendant(
        of: find.byType(HomeScreen),
        matching: find.textContaining('Read'),
      ),
      () => onScreen(find.byType(ChatScreen)),
      reason: 'blind mode should open the last conversation',
    );
    await pumpUntil(tester, find.text('Play'));
    expect(find.text('Replay'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // ---------------- Blind translator opens ----------------
    await tapUntil(
      tester,
      find.byTooltip('Record a voice message'),
      () => onScreen(find.byType(BlindTranslatorScreen)),
      reason: 'the blind voice translator should open',
    );
    await pumpUntil(tester, find.text('Tap to speak'));
    expect(find.textContaining('Voice message to'), findsWidgets);
  });

  testWidgets('settings and profile survive a cold restart',
      (WidgetTester tester) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Nothing is written here: a second cold start must read it all back.
    app.main();
    await tester.pump();
    await pumpUntil(tester, find.byType(HomeScreen));

    final String? raw = prefs.getString('sb_profile');
    expect(raw, isNotNull, reason: 'the profile must persist');
    final UserProfile profile = UserProfile.tryDecode(raw)!;
    expect(profile.name, 'Bea');
    // The role switched to blind at the end of the previous test.
    expect(profile.role, UserRole.blind);
    // The accessibility choices from the previous run are still in effect.
    expect(prefs.getDouble('pref_text_scale')!, greaterThan(1.0));
    expect(prefs.getBool('pref_high_contrast'), isTrue);
    // The conversation with the sample friend is still there.
    expect(
      prefs.getString('sb_friends'),
      contains(SampleFriendService.friendId),
    );
    expect(
      prefs.getString('sb_msgs_${SampleFriendService.friendId}'),
      isNotNull,
    );
  });

  // MUST STAY LAST: this one clears storage, so every test above it relies on
  // state this test destroys.
  testWidgets('a brand-new install walks through onboarding into setup',
      (WidgetTester tester) async {
    // Onboarding was the one path no test touched, and it is the very first
    // thing every user meets.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    app.main();
    await tester.pump();

    // 1. Onboarding is shown before anything else.
    await pumpUntil(tester, find.text('Next'));
    expect(
      find.text('Skip to Terms'),
      findsOneWidget,
      reason: 'the first slide should offer a shortcut to the terms',
    );

    // 2. Jump straight to the agreement slide.
    await tapUntil(
      tester,
      find.text('Skip to Terms'),
      () => onScreen(find.text('I agree to the Terms and Conditions')),
      reason: 'Skip to Terms should reach the agreement slide',
    );

    // 3. "Enter App" must stay disabled until the terms are accepted.
    final Finder enterApp = find.text('Enter App');
    expect(enterApp, findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.ancestor(
            of: enterApp,
            matching: find.byType(FilledButton),
          ))
          .onPressed,
      isNull,
      reason: 'entering the app must require accepting the terms',
    );

    await tapUntil(
      tester,
      find.byType(CheckboxListTile),
      () =>
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value ==
              true,
      reason: 'the terms checkbox should be tappable',
    );

    // 4. Accepting lands on Setup (role choice), never straight into the app.
    await tapUntil(
      tester,
      find.text('Enter App'),
      () => onScreen(find.byType(SetupScreen)),
      reason: 'Enter App should finish onboarding',
    );
    expect(find.text('I AM BLIND'), findsOneWidget);
    expect(find.text('I AM DEAF'), findsOneWidget);

    // Remembered, so a returning user skips onboarding entirely.
    expect(prefs.getBool('onboarding_seen'), isTrue);
    expect(prefs.getBool('accepted_terms'), isTrue);
  });
}
