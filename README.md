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

## Connecting two phones

Connecting always starts the same way — two people exchange a code. What
happens *after* that depends on whether the optional backend is configured.

**A. Same Wi-Fi (works in every build, no setup required)**

1. Put both phones on the **same Wi-Fi network** (a home router or phone
   hotspot both work; guest networks that isolate devices do not).
2. Open the app on both phones and keep it in the foreground.
3. One phone: **Add friend → Show my code**. The other: **Scan code** (or type
   the short code). Both confirm → the friend appears in both lists.
4. Chat. Messages travel directly over the local network — no internet, no
   server, no accounts.

**B. Different networks (requires the Supabase backend, see below)**

Same steps, but the code is resolved by the server and the friends can then
chat from anywhere over the internet. While the owner of the code is on the
"Show my code" screen, the scanner's request appears there and the owner taps
**Confirm connection** — that is the second half of the mutual confirmation.

Notes

* Discovery uses UDP broadcast (port 45123); delivery uses TCP (port 45124).
  Allow the app through any "AP isolation" / client-isolation setting.
* A **typed code** creates a placeholder entry; it upgrades to the real name
  automatically once the peer is reachable (immediately via the backend, or on
  the first shared Wi-Fi otherwise). Scanning the QR code skips that step.
* Messages sent while the friend is offline are kept and marked *Pending*;
  they are delivered automatically as soon as that friend is reachable again.

## Chat transport

Messages are stored on-device **before** delivery is attempted, so a
conversation survives a crash, a reboot or a lost connection.

Delivery goes through a `CompositeChatTransport` that tries, in order:

1. **LAN** — UDP broadcast discovery (port 45123) plus direct TCP (port 45124).
2. **Internet** — the Supabase backend, when it is configured.

The first transport that can deliver wins, so two phones on the same Wi-Fi keep
speaking directly (faster, private, no mobile data) and only friends on
different networks fall through to the backend. Incoming events from every
transport are merged, and duplicates are harmless: every message carrries a
client-generated id, so a redelivery — or a retry after a lost response — is
an idempotent no-op rather than a second copy.

If no transport can deliver, the message stays *Pending* and is flushed
automatically the moment that friend is reachable again (a LAN announce, an
internet heartbeat, or anything they send).

## Internet messaging (Supabase) — optional

The app ships **without** any backend credentials and is completely usable that
way. To enable long-distance chat, follow **[`supabase/README.md`](supabase/README.md)**
(run `schema.sql`, run `policies.sql`, enable anonymous sign-in, then build with
two `--dart-define` flags).

Key properties:

* **No directory, no search.** The only lookup is an exact invite-code match, so
  the "meet in person first" rule is preserved on the internet too.
* **No accounts.** An anonymous Supabase session — no email, phone number or
  social login is collected anywhere in the app.
* **Authorisation lives in the database**, not in the app. Row level security
  plus a handful of `SECURITY DEFINER` functions decide who may read or send
  what. See `supabase/policies.sql`.
* **A privileged key is refused.** `lib/backend/backend_config.dart` rejects a
  `service_role`/`sb_secret_` key at startup and keeps the app in offline mode,
  so a leaked APK can never bypass row level security.
* **Fail-soft.** An unreachable or misconfigured backend never blocks startup;
  Settings → Connection reports the real state.

## Built-in sample friend (for testing)

Chatting normally needs two phones meeting in person. To test the full flow on
one device, Settings → **Testing → Sample friend (TEST)** (also offered on the
empty Friends/Home screen) installs a local test contact:

* it always plays the **opposite role**, so both pipelines can be exercised;
* it sends one unread greeting, then answers every message you send;
* it is permanently marked `SAMPLE` / `TEST` and flagged in storage, so it can
  never be mistaken for a real person;
* nothing about it is transmitted — replies are generated on-device with the
  same translation engines, and it is excluded from the LAN transport;
* it can be removed like any other friend.

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
    transport/lan_transport.dart      UDP discovery + TCP chat for local delivery
    transport/remote_transport.dart   the same contract backed by Supabase
    transport/composite_transport.dart LAN first, internet second
  backend/                   optional Supabase layer (inert without credentials)
    backend_config.dart        --dart-define config + privileged-key guard
    remote_backend.dart        the contract (easy to fake in tests)
    disabled_remote_backend.dart  the "no credentials" implementation
    supabase_remote_backend.dart  the real client
supabase/                    schema.sql, policies.sql, setup guide
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

## Settings behaviour

* Text size, high contrast, theme, TTS rate/pitch/volume and every other
  preference applies **immediately** (no restart) and is written to disk, so it
  is restored on the next launch.
* The session is the single source of truth: a change updates memory, storage
  and the live TTS engine, and the theme layer re-renders on the same frame.
* Text-to-speech, visual notifications and vibration are three independent
  switches — turning the voice off never silences the visual alerts.
* **Reduce motion** disables route animations and sets
  `MediaQuery.disableAnimations` for the whole app.
* **Haptics** (Accessibility) is a master switch over **Vibration** (Alerts):
  both must be on before an incoming message buzzes.
* The emotion attached to a deaf user's message is cleared after sending, so a
  feeling is never silently re-used on a later message.
* An emotion that is missing or unrecognised stays **null**. It is never
  defaulted to "Happy", because a blind recipient must never hear a feeling the
  sender did not choose.
* Text-to-speech waits for an utterance to finish (bounded by a timeout), so the
  "Speaking..." indicator reflects reality and a wedged engine cannot hang the
  flow.

## Accessibility notes

* Blind mode's controls are ≥68 dp tall, are labelled for a screen reader and
  keep their tap action published on the semantics node (`excludeSemantics`
  hides a child button's own action, so `BigButton` re-declares `onTap`).
* Buttons wrap rather than ellipsise: a label is never cut off at large text
  sizes.
* Emotion colours are lightened on dark themes; at their original mid-tone
  values the badge label sat at roughly 2.5:1 contrast on a dark surface.
* Deaf mode never depends on sound: delivery status, emotion, unread counts and
  the QR code are all visible.

> Known limitation: the in-app font-size slider replaces the operating system's
> text scale rather than multiplying it, so a device set to a very large system
> font renders at the app's own maximum (1.4x). See "Future improvements" in the
> project report.

## Tests

```bash
flutter analyze
flutter test
```

| File | Covers |
| --- | --- |
| `test/widget_test.dart` | Acceptance A/B, the emotion prefix, translation rules |
| `test/app_services_test.dart` | Offline storage, invite-code expiry (acceptance D), sample-friend chat, settings sync |
| `test/settings_test.dart` | Every preference applies without a restart and survives a reload - including that high contrast changes the **rendered** colours and that reduce-motion really removes route animation |
| `test/backend_test.dart` | Backend config guard (a privileged key is refused), LAN/internet fallback order, backend-id routing, duplicate suppression, outbox retry |
| `test/ui_regression_test.dart` | `BigButton` stays a 68dp touch target, never truncates its label and remains **activatable by a screen reader**; emotion colours are legible on dark themes; an unknown emotion is never invented |

There is also an on-device end-to-end test that drives the real app with every
plugin active (set-up, sample friend, chat, both translators, live settings):

```bash
flutter emulators --launch <emulator-id>   # or plug in a phone
flutter test integration_test/app_flow_test.dart -d <device-id>
```

## Release build

```bash
# universal APK (all ABIs, ~425 MB)
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk

# per-ABI APKs — much smaller, use these for sharing
flutter build apk --release --split-per-abi
# output: app-arm64-v8a-release.apk (~167 MB), app-armeabi-v7a-release.apk (~126 MB)
```

Copies with friendlier names are kept in `dist/`.

To build **with** internet messaging enabled, add the two defines (see
`supabase/README.md`):

```bash
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

Two things to know before distributing:

* The release build uses the Flutter default Android signing configuration (see
  `android/app/build.gradle.kts`), i.e. the **debug keystore**. That is fine for
  handing an APK to workmates; replace it with your own keystore before
  publishing anywhere public.
* The application id is still `com.example.smartbridgeapp`. Changing it makes
  the APK a *different* app to Android — an existing install will not upgrade,
  it will sit alongside. Change it once, before the first real distribution.
