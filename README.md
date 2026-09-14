# SmartBridge Messages

SmartBridge Messages is an accessibility-focused messaging app that lets a
**blind person** and a **deaf person** hold one shared conversation.

> **Different ways of communicating, one shared conversation.**

It builds on the original SmartBridge sign-language translator: the camera
sign-recognition pipeline, speech-to-text, text-to-speech, onboarding and all
accessibility settings are preserved and reachable inside the new app
(Settings → Sign tools).

## Communication flows

| Direction | Pipeline |
| --- | --- |
| Blind → Deaf | Voice → Speech-to-Text → **simplified** short English → preview → send |
| Deaf → Blind | Typed input → **improved** natural English → emotion picker → preview → send → spoken aloud (emotion first) |

Translation is deterministic, local and rule-based (no network): the same
input always produces the same output, and the chat always keeps **both** the
original and the translated text. Emotions (Happy / Sad / Angry / Shy) are
always chosen manually — the app never infers feelings.

## Friend system (offline-first, meet in person)

* No public search, directory or random invites exist anywhere.
* One side shows an expiring invite code (QR + short code, 30-minute TTL).
* The other side scans the QR or types the short code, then **both confirm**.
* Codes carry only display name, role and id — never contact details.
* Removing a friend deletes the conversation and blocks stale codes.

## Chat transport

Messages are stored on-device **before** delivery. Live delivery uses the
local Wi-Fi: UDP broadcast discovery (port 45123) plus direct TCP messages
(port 45124). If a friend is unreachable the message stays marked *Pending*
and is retried automatically — nothing is ever lost while offline.

## Screens

1. Welcome / Onboarding (original flow, preserved)
2. Setup — "I AM BLIND" / "I AM DEAF"; the whole UI adapts
3. Home — blind: giant spoken buttons; deaf: conversation list + unread badges
4. Friends — list, open chat, remove friend
5. Add Friend — expiring QR, typed fallback, confirmation
6. Chat — bubbles with original + translated text, emotion badges, delivery
   status; blind mode adds Play / Replay / Pause / Stop TTS controls
7. Blind Translator — big microphone, live transcript, simplified preview
8. Deaf Translator — typed input, live improvement, emotion picker, preview
9. Settings — profile, role, TTS rate/pitch/volume, notifications, vibration,
   font size, high contrast, reduce motion, delete conversations, remove
   friends, privacy notes, and the original sign-tool settings

## Project structure

```
lib/
  main.dart                  entry point + service wiring
  database/local_database.dart   offline-first storage (profile/friends/messages)
  models/                    emotion, user profile, chat message, UI prefs
  screens/                   setup, home, friends, add friend, chat, translators, settings
    legacy/                  preserved SmartBridge screens (onboarding, sign translator, ...)
  services/                  translation, stt, tts, session, friends, chat, connectivity
    transport/lan_transport.dart  UDP discovery + TCP chat for local delivery
  widgets/                   theme, branding, message bubble, emotion badge, big buttons
```

## Permissions

Microphone, camera and notifications are requested **only when the related
feature is first used**, never at startup. Storage access is not required;
all data lives in app-private storage.

## Error handling

* Microphone denied → "Microphone permission is required for voice messages." with Open Settings.
* Speech not understood → "We couldn't understand the speech. Please try again."
* Translation failure → the original text is sent instead of dropping the message.
* Offline → banner: "You're offline. Messages will be synchronized when connection is restored."
* Invalid/expired code → "Invalid or expired friend code."

## Run

```bash
flutter pub get
flutter run            # Android is the primary target
```

## Tests

```bash
flutter test           # includes acceptance tests A (blind simplify) and
                       # B (deaf improve + emotion prefix)
flutter analyze
```
