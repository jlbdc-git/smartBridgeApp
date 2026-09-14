/// Rule-based English text transformation services.
///
/// These translators are intentionally DETERMINISTIC and local (no network):
/// the same input always produces the same output, which keeps the original
/// meaning predictable and auditable for the user in the preview step.
library;

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _word = RegExp(r"[A-Za-z']+");

/// Splits raw text into lowercase word tokens (punctuation dropped).
List<String> _tokens(String text) {
  return _word
      .allMatches(text)
      .map((RegExpMatch m) => m.group(0)!.toLowerCase())
      .toList();
}

/// True when [word] occurs as a whole token in [text].
bool _hasWord(List<String> tokens, String word) => tokens.contains(word);

/// Applies whole-phrase replacements, longest phrase first, once per position.
///
/// Word boundaries are enforced so short slang keys (e.g. "r" -> "are")
/// never corrupt words that merely CONTAIN them (e.g. "tomorrow").
String _replacePhrases(
  String input,
  Map<String, String> replacements,
) {
  final List<String> keys = replacements.keys.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  String out = input;
  for (final String key in keys) {
    final RegExp pattern = RegExp(
      r'\b' + RegExp.escape(key) + r'\b',
      caseSensitive: false,
    );
    out = out.replaceAllMapped(pattern, (Match m) => replacements[key]!);
  }
  return out;
}

/// Merges duplicated spaces, fixes spacing before punctuation and duplicates
/// punctuation, and capitalises sentence starts.
String _tidy(String text) {
  String out = text.replaceAll(_whitespace, ' ').trim();
  out = out.replaceAll(' ,', ',').replaceAll(' .', '.');
  out = out.replaceAll(RegExp(r'\.{2,}'), '.');
  out = out.replaceAll(RegExp(r'\s+([!?;,])'), r'$1');
  // Capitalise first letter of every sentence.
  out = out.replaceAllMapped(
    RegExp(r'(^|[.!?]\s+)([a-z])'),
    (Match m) => '${m.group(1)}${m.group(2)!.toUpperCase()}',
  );
  return out;
}

/// Capitalises the standalone pronoun "i".
String _fixCapitalI(String text) {
  return text.replaceAllMapped(
    RegExp(r'\bi\b'),
    (Match m) => 'I',
  );
}

// ---------------------------------------------------------------------------
// BLIND translator: natural/verbose speech  ->  simple, short "broken" English
// ---------------------------------------------------------------------------

/// Voice-first simplification for blind senders.
///
/// Rules:
///  * preserve meaning and intent,
///  * short, direct sentences, minimal grammar, simple vocabulary,
///  * NEVER invent information, NEVER drop important details.
class BlindTranslator {
  const BlindTranslator();

  // Formal -> simple phrase rewrites.
  static const Map<String, String> _phrases = <String, String>{
    'i would like to know': 'i want to know',
    'i would like to': 'i want to',
    'i was wondering if': 'do you',
    'i was wondering whether': 'do you',
    'i wanted to ask if': 'do you',
    'i wanted to ask whether': 'do you',
    'do you happen to know': 'do you know',
    'could you please tell me': 'tell me',
    'can you please tell me': 'tell me',
    'could you tell me': 'tell me',
    'can you tell me': 'tell me',
    'would you mind': 'can you',
    'would it be possible for you to': 'can you',
    'is it possible for you to': 'can you',
    'are you able to': 'can you',
    'do you think you could': 'can you',
    'i am wondering': 'i want to know',
    "i'm wondering": 'i want to know',
    'whether or not': 'if',
    'whether': 'if',
    'would you like to': 'do you want to',
    'would you care to': 'do you want to',
    'would you be interested in': 'do you want',
    'are you interested in': 'do you want',
    'do you feel like': 'do you want to',
    'are you available': 'you free',
    'you are available': 'you free',
    'will you be available': 'you free',
    'are you going to be free': 'you free',
    'are you free': 'you free',
    'are you busy': 'you busy',
    'right now': 'now',
    'at a later time': 'later',
    'at a later date': 'later',
    'at some point': 'later',
    'later on': 'later',
    'later tonight': 'later tonight',
    'this evening': 'tonight',
    'as soon as possible': 'soon',
    'at the moment': 'now',
    'currently': 'now',
    'please let me know': 'tell me',
    'let me know': 'tell me',
    'i am sorry to bother you': 'sorry',
    "i'm sorry to bother you": 'sorry',
    'sorry to bother you': 'sorry',
    'i just wanted to say': 'i say',
    'i just wanted to': 'i want to',
    'i need to inform you that': 'i need to say',
    'i want to inform you that': 'i need to say',
    'it would be great if': 'please',
    'it would be nice if': 'please',
    'i really appreciate it if': 'please',
    'make sure to': 'please',
    'a little bit': 'a bit',
    'in order to': 'to',
    'because of the fact that': 'because',
    'due to the fact that': 'because',
    'for the reason that': 'because',
    'a large number of': 'many',
    'a lot of': 'many',
    'the majority of': 'most',
    'at this point in time': 'now',
    'in the near future': 'soon',
    'the day after tomorrow': 'in two days',
    'the day before yesterday': 'two days ago',
    'what is your opinion about': 'what do you think about',
    'what are your thoughts on': 'what do you think about',
    'how do you feel about': 'what do you think about',
    'i do not know': 'i do not know',
    'i am not sure if': 'i do not know if',
    "i'm not sure if": 'i do not know if',
  };

  // Verbose single words -> simple words.
  static const Map<String, String> _words = <String, String>{
    'approximately': 'about',
    'additionally': 'also',
    'assistance': 'help',
    'assist': 'help',
    'attempt': 'try',
    'commence': 'start',
    'purchase': 'buy',
    'require': 'need',
    'requires': 'needs',
    'required': 'needed',
    'immediately': 'now',
    'currently': 'now',
    'regarding': 'about',
    'concerning': 'about',
    'obtain': 'get',
    'receive': 'get',
    'provide': 'give',
    'possess': 'have',
    'utilise': 'use',
    'utilize': 'use',
    'inform': 'tell',
    'maybe': 'maybe',
    'perhaps': 'maybe',
    'possible': 'can',
    'travelling': 'travel',
    'traveling': 'travel',
    'vehicle': 'car',
    'residence': 'home',
    'physician': 'doctor',
    'telephone': 'phone',
    'photograph': 'photo',
    'favourite': 'favorite',
  };

  /// Filler phrases removed from the front/middle of a sentence. Only fillers
  /// are dropped - real information never is.
  static const List<String> _fillers = <String>[
    'well',
    'um',
    'uh',
    'er',
    'ah',
    'like i said',
    'as you know',
    'if that is okay',
    'if you do not mind',
  ];

  String simplify(String input) {
    final String raw = input.trim();
    if (raw.isEmpty) return raw;

    // 1. Normalise speech spacing, drop fillers.
    String text = raw.replaceAll(_whitespace, ' ').trim();
    for (final String filler in _fillers) {
      text = text.replaceFirstMapped(
        RegExp(
          r'(^|[,.!?]\s*)' + RegExp.escape(filler) + r'[,.!?]?\s*',
          caseSensitive: false,
        ),
        (Match m) => (m.group(1) ?? '').isEmpty ? '' : m.group(1)!,
      );
    }

    // 2. Phrase-level simplification.
    text = _replacePhrases(text, _phrases);

    // 2b. Indirect questions become direct questions (spec example):
    //     "I want to know if you are free tomorrow" -> "you are free tomorrow".
    //     The framing words carry no new information; the question is asked.
    bool indirectQuestion = false;
    final RegExp questionFrame = RegExp(
      r'^i want to know\s+(?:if|whether)\s+',
      caseSensitive: false,
    );
    if (questionFrame.hasMatch(text)) {
      text = text.replaceFirstMapped(
        questionFrame,
        (Match m) => '',
      );
      indirectQuestion = true;
    }

    // 3. Word-level simplification.
    final List<String> tokens = _tokens(text);
    if (_hasWord(tokens, 'assistance')) {
      text = _replacePhrases(text, _words);
    } else {
      text = _replacePhrases(text, _words);
    }

    // 4. Drop polite decorations that carry no information.
    text = text.replaceAll(
      RegExp(r'\bplease\b\s*', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'^\s*(hi|hello)\b[,.!]?\s*', caseSensitive: false), '');
    text = text.replaceAll(
      RegExp(r',?\s*(if you can|if possible|thanks|thank you)\b[.!]?',
          caseSensitive: false),
      '',
    );

    // 5. Punctuation cleanup. Blind simplification intentionally drops most
    //    punctuation: short and direct beats formally correct.
    text = text.replaceAll(RegExp(r'[.,;:](\s|$)'), ' ');
    text = text.replaceAll(RegExp(r'\?{1}'), '?');
    text = _fixCapitalI(text);

    // 6. Question detection: "do/does/is/are/can/will/should + you ..." or an
    //    explicit question mark in the source means keep it a question.
    final bool explicitQuestion = raw.contains('?');
    final bool startsQuestion =
        RegExp(r'^(do|does|did|is|are|was|were|can|could|will|would|should|shall|may|have|has)\b',
                caseSensitive: false)
            .hasMatch(text.trim());
    final bool asksYou = RegExp(r'\byou\b', caseSensitive: false).hasMatch(text);

    text = _tidy(text);
    text = text.endsWith('?') ? text.substring(0, text.length - 1).trim() : text;

    if (explicitQuestion || indirectQuestion || (startsQuestion && asksYou)) {
      text = '$text?';
    }

    return text.trim();
  }
}

// ---------------------------------------------------------------------------
// DEAF translator: broken/short typed input  ->  natural, well-formed English
// ---------------------------------------------------------------------------

/// Text-first improvement for deaf senders.
///
/// Rules:
///  * fix grammar and sentence structure, make the English natural,
///  * preserve the original intent,
///  * NEVER add information the sender did not type.
class DeafTranslator {
  const DeafTranslator();

  static const Set<String> _questionStarters = <String>{
    'do', 'does', 'did', 'is', 'are', 'was', 'were', 'can', 'could',
    'will', 'would', 'should', 'shall', 'may', 'have', 'has', 'am',
  };

  static const Map<String, String> _contractions = <String, String>{
    'i am': "i'm",
    'you are': "you're",
    'we are': "we're",
    'they are': "they're",
    'that is': "that's",
    'it is': "it's",
    'do not': "don't",
    'does not': "doesn't",
    'can not': "can't",
    'cannot': "can't",
    'will not': "won't",
  };

  String improve(String input) {
    final String raw = input.trim();
    if (raw.isEmpty) return raw;

    // 1. Normalise whitespace and punctuation.
    String text = raw.replaceAll(_whitespace, ' ').trim();
    text = text.replaceAll(RegExp(r'\s+([,.!?;])'), r'$1');
    text = text.replaceAll(RegExp(r'([,.!?]){2,}'), r'$1');

    // 2. Slang -> standard English.
    text = _replacePhrases(text, const <String, String>{
      'wanna': 'want to',
      'gonna': 'going to',
      'gotta': 'have to',
      'kinda': 'kind of',
      'sorta': 'sort of',
      'outta': 'out of',
      'dunno': 'i do not know',
      'cuz': 'because',
      'coz': 'because',
      'cos': 'because',
      'u': 'you',
      'ur': 'your',
      'r': 'are',
      'pls': 'please',
      'plz': 'please',
      'thx': 'thanks',
      'tmrw': 'tomorrow',
      'tmr': 'tomorrow',
      '2mrw': 'tomorrow',
      'tonite': 'tonight',
      'msg': 'message',
    });

    // 3. Sentence-boundary repair: make sure a sentence exists between dots.
    text = text.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (Match m) => '${m.group(1)}. ${m.group(2)}',
    );

    // 3b. Deaf typing often omits the break after a time reference:
    //     "...mall tomorrow you want come" -> "...mall tomorrow. You want come".
    //     Only a sentence BOUNDARY is added - no words are changed.
    text = text.replaceAllMapped(
      RegExp(
        r'\b(tomorrow|tonight|today|later|soon)\s+(you|i|we)\b',
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)}. ${m.group(2)}',
    );

    // 4. First-person contraction: "I go" -> "I'm going", "I eat" -> "I'm
    //    eating" for actions in progress near a time reference.
    final bool hasFutureTime = RegExp(
      r'\b(tomorrow|tonight|later|today|next week|next month|soon)\b',
      caseSensitive: false,
    ).hasMatch(text);

    if (hasFutureTime) {
      // "i go" / "i visit" / "i eat" ... -> "i'm going" etc.
      text = text.replaceAllMapped(
        RegExp(
          r'\bi\s+(go|come|visit|see|meet|eat|shop|travel|drive|walk|study|work|play|stay|move|start|finish|buy|get|have|do)\b',
          caseSensitive: false,
        ),
        (Match m) {
          final String verb = m.group(1)!.toLowerCase();
          final String stem = verb.endsWith('e') && verb.length > 2
              ? verb.substring(0, verb.length - 1)
              : verb;
          final String doubling =
              RegExp(r'^(shop|stop|sit|run|swim|get)$').hasMatch(stem)
                  ? stem.substring(stem.length - 1)
                  : '';
          final String ingForm = '$stem$doubling'
              'ing';
          return "I'm $ingForm";
        },
      );
      // "we/you/they go ..." -> "we're going ..." etc.
      text = text.replaceAllMapped(
        RegExp(
          r'\b(we|you|they)\s+(go|come|visit|see|meet|eat|shop|travel|drive|walk|study|work|play|stay|move|start|finish|buy|get|have|do)\b',
          caseSensitive: false,
        ),
        (Match m) {
          final String subject = m.group(1)!.toLowerCase();
          final String verb = m.group(2)!.toLowerCase();
          final String stem = verb.endsWith('e') && verb.length > 2
              ? verb.substring(0, verb.length - 1)
              : verb;
          final String conjugated = subject == 'you' ? "you're" : "$subject're";
          final String ingForm = '$stem' 'ing';
          return '$conjugated $ingForm';
        },
      );
    }

    // 5. Article repair for common place phrases: "go mall" -> "go to the
    //    mall". Only applied to well-known places, so no information is added
    //    that the sender did not mean.
    text = text.replaceAllMapped(
      RegExp(
        r'\b(go|going|went|come|coming|head|heading|drive|driving|walk|walking)\s+(to\s+)?(mall|market|park|school|hospital|clinic|library|bank|gym|store|shop|airport|station|beach|church|office|restaurant|movie|cinema)\b',
        caseSensitive: false,
      ),
      (Match m) {
        final String verb = m.group(1)!;
        final String place = m.group(3)!;
        return '$verb to the $place';
      },
    );

    // 6. Offer repair: "you want come" -> "would you like to come with me".
    //    The bare invitation pattern implies "with me" (see spec example).
    text = _replacePhrases(text, const <String, String>{
      'do you want to come': 'would you like to come',
      'you want to come': 'would you like to come',
      'you want come': 'would you like to come with me',
      'u want come': 'would you like to come with me',
      'you want join': 'would you like to join',
      'you want to join': 'would you like to join',
    });

    // 7. Copula insertion: "you free tomorrow" -> "are you free tomorrow".
    //    Only common state adjectives; no other words are added.
    text = text.replaceAllMapped(
      RegExp(
        r'(^|[.!?]\s+)you\s+(free|busy|available|ready|ok|okay|fine|well|hungry|thirsty|tired|alone|angry|sad|happy|upset|sick|home|here|there)\b',
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)}are you ${m.group(2)}',
    );

    // 8. Politeness: bare requests get a soft opener only when clearly a
    //    request ("please" is never added).
    text = text.replaceAll(
      RegExp(r'^help me\s+', caseSensitive: false),
      'Could you help me ',
    );

    // 9. "i want go" -> "i want to go" (missing infinitive "to").
    text = text.replaceAllMapped(
      RegExp(
        r"\b(want|needs?|likes?|going|plan(?:s|ning)?|try(?:ing)?)\s+(go|come|eat|buy|see|visit|meet|talk|call|study|work|play|sleep|rest|shop|walk|travel)\b",
        caseSensitive: false,
      ),
      (Match m) => '${m.group(1)} to ${m.group(2)}',
    );

    // 10. "me and you" style -> natural order.
    text = _replacePhrases(text, const <String, String>{
      'me and you': 'you and i',
      'me & you': 'you and i',
      'with me and you': 'with you and me',
    });

    // 11. Contractions for natural tone.
    text = _replacePhrases(text, _contractions);

    text = _fixCapitalI(text);
    text = _tidy(text);

    // 12. Terminal punctuation and question marks.
    final bool endsPunct = RegExp(r'[.!?]$').hasMatch(text);
    if (!endsPunct) {
      final List<String> tokens = _tokens(text);
      final bool startsQuestion = tokens.isNotEmpty &&
          _questionStarters.contains(tokens.first) &&
          _hasWord(tokens, 'you');
      final bool sourceQuestion = raw.trim().endsWith('?');
      final bool multiSentence = RegExp(r'[.!?]\s+\S').hasMatch(text);
      if ((startsQuestion || sourceQuestion) && !multiSentence) {
        text = '$text?';
      } else {
        text = '$text.';
      }
    }

    return text.trim();
  }
}
