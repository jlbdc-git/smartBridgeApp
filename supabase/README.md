# Supabase backend — setup guide

This folder contains the **database side** of SmartBridge Messages: the schema,
the row level security policies, and the three SECURITY DEFINER functions that
make the QR/short-code friend system work over the internet.

**Nothing in this folder runs automatically.** The app works completely without
it (offline + local Wi-Fi). These files are what you run once, when you are
ready to turn on internet messaging.

---

## 1. What the app does *without* any of this

Verified, working today:

* Chat, translation, emotions, TTS/STT, all settings, all accessibility.
* Friend connection over **local Wi-Fi** (UDP discovery + direct TCP).
* Offline-first storage: every message is written to the device before any
  delivery is attempted.
* The built-in **Sample Friend (TEST)** contact for single-device testing.

The app never attempts a network call it cannot make: with no credentials the
whole backend layer is inert (`DisabledRemoteBackend`).

---

## 2. What turns on once the backend is configured

* Two confirmed friends can chat **from different networks**, through the
  Supabase project instead of the local Wi-Fi.
* The friend connection itself can be made when the two phones are not on the
  same Wi-Fi (the QR/short-code exchange still has to happen in person).
* Read status travels between devices.
* Removing a friend revokes their access on the server, so they can no longer
  read or send anything.

Delivery order is **LAN first, then internet**. Two phones on the same Wi-Fi
keep talking directly — faster, private, and no mobile data is spent.

---

## 3. Setup steps

### 3.1 Create / open the project

In the Supabase dashboard, open (or create) the project you intend to use.

### 3.2 Run the schema

SQL Editor → New query → paste the whole of **`schema.sql`** → Run.

### 3.3 Run the policies

SQL Editor → New query → paste the whole of **`policies.sql`** → Run.

> Both are idempotent (`create ... if not exists`, `create or replace`,
> `drop trigger if exists`), so re-running them after an update is safe.

### 3.4 Enable anonymous sign-in

Authentication → Sign In / Providers → enable **Anonymous sign-ins**.

The app uses an anonymous session on purpose: the spec forbids collecting
unnecessary personal data, so there is no email, password, phone number or
social login anywhere in the app. If this is left disabled, the app stays in
its offline/LAN mode and Settings will show the backend as unavailable.

### 3.5 Verify Realtime is on for the three tables

Database → Replication → confirm `messages`, `friendships` and `profiles`
appear in the `supabase_realtime` publication. `schema.sql` adds them, but the
extension must be enabled for the project.

### 3.6 Get the credentials

Project Settings → API Keys. You need:

| Value | Where it goes | Notes |
|---|---|---|
| Project URL | `SUPABASE_URL` | `https://<ref>.supabase.co` |
| **Publishable / anon** key | `SUPABASE_ANON_KEY` | safe in a client — RLS protects the data |

### 3.7 Build with the credentials

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_KEY
```

For day-to-day development:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```

Without those two flags the build is a normal offline/LAN build.

---

## 4. ⚠️ Never ship a secret or service-role key

`lib/backend/backend_config.dart` **refuses to configure the app** if the key
looks privileged:

* a JWT whose payload contains `"role":"service_role"` (or `supabase_admin`), or
* a modern key beginning with `sb_secret_`.

In that case Settings shows *“Rejected: SUPABASE_ANON_KEY is a privileged
key”* and the app keeps running in offline/LAN mode. This is deliberate: a
service-role key bypasses every row level security policy, so a single leaked
APK would expose the whole database.

Use the **publishable / anon** key only. `SUPABASE_SERVICE_ROLE_KEY` must never
appear in a mobile client, in this repository, or in a build command.

The URL must be `https://` (plain `http://` is accepted only for a local
Supabase instance on loopback, so messages cannot be read or altered in
transit from a real device).

---

## 5. How authorization actually works

The mobile client is treated as hostile — anyone can extract the publishable
key from an APK and call the API with their own session. Therefore every rule
is enforced in the database:

| Rule | Enforced by |
|---|---|
| A user can only read/write their own profile | `profiles` policies |
| No user directory, no search | there is simply no such endpoint; the only lookup is `lookup_invite_code(exact_code)` |
| Possessing a code is required to start a connection | `friendships` has **no** client insert policy — only `request_friendship(code)` can create a row, and it requires a live code |
| Only the invited side can accept | `confirm_friendship()` checks `addressee_id = auth.uid()` |
| Messages only between confirmed friends | `messages` insert policy calls `are_confirmed_friends()` |
| Only the receiver can mark read | `messages` update policy |
| A delivered message can never be edited | `messages_guard_update` trigger |
| Removing a friend really revokes access | `revoke_friendship()` deletes the row; the insert policy then fails |

`profiles` exposes **only** a display name, a role and a rotating invite code.
Nothing else is collected anywhere in the app.

---

## 6. Status: what is and is not verified

| Item | Status |
|---|---|
| Schema SQL is syntactically valid | **NOT TESTED** — no project has been run against yet |
| RLS policies block cross-user access | **NOT TESTED** — needs a real project |
| Realtime delivery between two devices | **REQUIRES SUPABASE CONFIGURATION** |
| Code lookup / request / confirm RPCs | **REQUIRES SUPABASE CONFIGURATION** |
| The app compiles, runs and stays offline-clean with no credentials | **PASSED** (automated tests + release APK) |
| A privileged key is refused by the client | **PASSED** (unit tests) |
| The client-side transport, routing and outbox logic | **PASSED** (unit tests against a fake backend) |

Nobody has connected this to a real project yet. Treat the first setup as a
test run, and start with two test accounts.
