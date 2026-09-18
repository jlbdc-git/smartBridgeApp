import 'dart:convert';

/// Compile-time configuration for the optional Supabase backend.
///
/// Everything here is supplied at build time, never committed:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// WHY COMPILE-TIME: the anon key is not a secret in the Supabase model (row
/// level security is what actually protects the data), but keeping it out of
/// the repository still means a leaked build artefact cannot be pointed at a
/// different project, and it keeps staging and production builds separate.
///
/// THE APP MUST WORK WITH NO CONFIGURATION AT ALL. When [isConfigured] is
/// false the whole backend layer is inert: the app behaves exactly like the
/// offline/LAN-only build, and nothing tries to reach the network.
class BackendConfig {
  const BackendConfig({required this.url, required this.anonKey});

  /// Reads the configuration from `--dart-define` values.
  /// Defaults to empty strings, i.e. "not configured".
  factory BackendConfig.fromEnvironment() {
    return const BackendConfig(
      url: String.fromEnvironment('SUPABASE_URL'),
      anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  final String url;
  final String anonKey;

  /// True only when a URL and a key were both supplied AND the key is safe to
  /// ship inside a mobile client.
  bool get isConfigured => problem == BackendConfigProblem.none;

  /// Everything that is wrong with the current configuration, if anything.
  /// [BackendConfigProblem.none] means the configuration is usable.
  BackendConfigProblem get problem {
    if (url.trim().isEmpty) return BackendConfigProblem.missingUrl;
    if (anonKey.trim().isEmpty) return BackendConfigProblem.missingKey;
    if (!_isAcceptableUrl(url.trim())) {
      return BackendConfigProblem.insecureUrl;
    }
    // The single most dangerous mistake possible here: shipping a key that
    // bypasses row level security. Fail loudly instead of silently exposing
    // every user's data.
    if (isPrivilegedKey(anonKey.trim())) {
      return BackendConfigProblem.privilegedKey;
    }
    return BackendConfigProblem.none;
  }

  /// Human readable explanation, shown in Settings so a developer running a
  /// misconfigured build sees it immediately instead of debugging silence.
  String get problemMessage {
    switch (problem) {
      case BackendConfigProblem.none:
        return 'Configured';
      case BackendConfigProblem.missingUrl:
        return 'Not configured (no SUPABASE_URL)';
      case BackendConfigProblem.missingKey:
        return 'Not configured (no SUPABASE_ANON_KEY)';
      case BackendConfigProblem.insecureUrl:
        return 'Rejected: SUPABASE_URL must use https';
      case BackendConfigProblem.privilegedKey:
        return 'Rejected: SUPABASE_ANON_KEY is a privileged key';
    }
  }

  /// Only https is accepted, so messages cannot be read or altered in transit.
  /// Plain http is tolerated for a local Supabase instance on loopback.
  static bool _isAcceptableUrl(String value) {
    if (value.startsWith('https://')) return true;
    return value.startsWith('http://localhost') ||
        value.startsWith('http://127.0.0.1') ||
        value.startsWith('http://10.0.2.2'); // Android emulator loopback
  }

  /// Detects a key that must never exist in a client binary.
  ///
  /// Two generations of Supabase keys exist:
  ///  * JWT style  - the payload carries `"role":"anon"` (safe) or
  ///                 `"role":"service_role"` (catastrophic in a client).
  ///  * New style  - `sb_publishable_...` (safe) vs `sb_secret_...`.
  static bool isPrivilegedKey(String key) {
    if (key.startsWith('sb_secret_')) return true;

    final Map<String, dynamic>? payload = decodeJwtPayload(key);
    if (payload == null) return false; // not a JWT: nothing to assert
    final Object? role = payload['role'];
    if (role is! String) return false;
    return role == 'service_role' || role == 'supabase_admin';
  }

  /// Decodes the (unverified) payload of a JWT so its `role` claim can be
  /// inspected. Returns null when the value is not a three part JWT.
  ///
  /// Signature verification is deliberately NOT attempted: this check only
  /// needs to catch a key the project owner pasted by mistake, and the server
  /// is the real authority. It is a guard rail, not an authorization decision.
  static Map<String, dynamic>? decodeJwtPayload(String token) {
    final List<String> parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final Object? decoded =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Malformed token: treat as "cannot assert anything".
    }
    return null;
  }
}

/// The outcome of validating a [BackendConfig].
enum BackendConfigProblem {
  none,
  missingUrl,
  missingKey,
  insecureUrl,
  privilegedKey,
}
