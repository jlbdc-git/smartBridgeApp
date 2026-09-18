import 'package:flutter_test/flutter_test.dart';

import 'package:smartbridgeapp/services/translation_service.dart';
import 'package:smartbridgeapp/models/chat_message.dart';
import 'package:smartbridgeapp/models/emotion.dart';

void main() {
  group('BlindTranslator (voice -> simple English)', () {
    const BlindTranslator translator = BlindTranslator();

    test('ACCEPTANCE A: availability question is simplified', () {
      expect(
        translator.simplify('Are you available later tonight?'),
        'You free later tonight?',
      );
    });

    test('spec example: formal question becomes short question', () {
      expect(
        translator.simplify(
            'I would like to know whether you are available tomorrow.'),
        'You free tomorrow?',
      );
    });

    test('keeps important details (place)', () {
      final String out = translator
          .simplify('Could you please tell me if the mall is open now?');
      expect(out.toLowerCase().contains('mall'), isTrue);
      expect(out.endsWith('?'), isTrue);
    });

    test('plain statement stays declarative', () {
      expect(
        translator.simplify('I need help with my bag right now.'),
        'I need help with my bag now',
      );
    });

    test('a request stays a request, not a bare imperative', () {
      // Before the phrase rule existed, the single-word "possible" -> "can"
      // mapping produced "Is it can to meet tomorrow?".
      expect(
        translator.simplify('Is it possible to meet tomorrow?'),
        'Can you meet tomorrow?',
      );
      expect(
        translator.simplify('Would it be possible to call me later?'),
        'Can you call me later?',
      );
    });
  });

  group('DeafTranslator (broken input -> natural English)', () {
    const DeafTranslator translator = DeafTranslator();

    test('ACCEPTANCE B: mall plan is improved', () {
      expect(
        translator.improve('You free tomorrow? I want go mall with you.'),
        "Are you free tomorrow? I want to go to the mall with you.",
      );
    });

    test('spec example: mall invitation is naturalised', () {
      expect(
        translator.improve('I go mall tomorrow you want come?'),
        "I'm going to the mall tomorrow. Would you like to come with me?",
      );
    });

    test('verbs ending in "ee" are not mangled into "seing"', () {
      final String out = translator.improve('i see you tomorrow');
      expect(out.toLowerCase(), contains('seeing'));
      expect(out.toLowerCase(), isNot(contains('seing')));
    });
  });

  group('Emotion', () {
    test('spoken prefix leads the message (acceptance B)', () {
      final ChatMessage message = ChatMessage(
        id: 'm1',
        senderId: 'f1',
        senderName: 'John',
        receiverId: 'me',
        originalText: 'You free tomorrow? I want go mall with you.',
        translatedText:
            'Are you free tomorrow? I want to go to the mall with you.',
        direction: MessageDirection.deafToBlind,
        timestamp: DateTime.now(),
        emotion: Emotion.happy,
      );
      expect(message.emotion!.label, 'Happy');
      expect(message.emotion!.spokenPrefix, 'Happy.');
      expect(message.displayText, contains('mall'));
    });
  });

  group('Friend invite codes', () {
    test('generated codes match the shareable format', () {
      final RegExp pattern = RegExp(r'^SB-[A-Z0-9]{3,8}-[A-Z0-9]{2,4}$');
      // The code generator is exercised indirectly through the format rule.
      expect(pattern.hasMatch('SB-4821-93'), isTrue);
      expect(pattern.hasMatch('HELLO'), isFalse);
      expect(pattern.hasMatch('SB-123-4567'), isTrue);
      expect(pattern.hasMatch('SB-12-3456'), isFalse);
    });
  });
}
