import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Why the device could not produce a Google ID token.
enum GoogleIdTokenFailure {
  cancelled,
  noAccount,
  unavailable,
  misconfigured,
  unknown,
}

class GoogleIdTokenException implements Exception {
  const GoogleIdTokenException(this.code, this.message);
  final GoogleIdTokenFailure code;
  final String message;

  @override
  String toString() => 'GoogleIdTokenException(${code.name}, $message)';
}

/// An ID token for the web client, plus the raw nonce whose SHA-256 was
/// sent to Google (Supabase checks it), when one was used.
class GoogleIdToken {
  const GoogleIdToken(this.idToken, {this.rawNonce});
  final String idToken;
  final String? rawNonce;
}

/// Where Google ID tokens come from. The production source wraps the
/// `google_sign_in` plugin; tests substitute their own.
abstract class GoogleIdTokenSource {
  /// Shows Google's account picker (Credential Manager on Android) and
  /// returns the ID token for the configured web client.
  Future<GoogleIdToken> idToken();

  /// Forgets the picked account so the next [idToken] asks again.
  Future<void> signOut();
}

/// [GoogleIdTokenSource] over `google_sign_in` 7 (Credential Manager on
/// Android, initialize-once).
///
/// Nonce policy: the plugin takes one nonce at [GoogleSignIn.initialize],
/// so there is one per process. The raw value stays here and goes to
/// Supabase; its SHA-256 goes to Google and comes back in the token's
/// `nonce` claim, which Supabase verifies. Pass `useNonce: false` only if
/// a provider setting demands it ("Skip nonce check" exists for that).
///
/// No access token is requested: `authenticate()` returns the ID token
/// alone, and the plugin only shows a second consent prompt when
/// `authorizationClient.authorizeScopes` asks for scopes, which nothing
/// here does. Supabase accepts the ID token by itself.
class PluginGoogleIdTokenSource implements GoogleIdTokenSource {
  PluginGoogleIdTokenSource({
    required this.serverClientId,
    this.useNonce = true,
  });

  /// The Google Cloud **Web** OAuth client ID (also the Supabase provider's).
  final String serverClientId;
  final bool useNonce;

  String? _rawNonce;
  Future<void>? _initialized;

  Future<void> _ensureInitialized() => _initialized ??= () async {
    if (useNonce) _rawNonce = generateNonce();
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
      nonce: _rawNonce == null ? null : sha256Hex(_rawNonce!),
    );
  }();

  @override
  Future<GoogleIdToken> idToken() async {
    await _ensureInitialized();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      throw mapException(e);
    }
    final token = account.authentication.idToken;
    if (token == null) {
      throw const GoogleIdTokenException(
        GoogleIdTokenFailure.unknown,
        'Google returned no ID token',
      );
    }
    return GoogleIdToken(token, rawNonce: _rawNonce);
  }

  @override
  Future<void> signOut() async {
    if (_initialized == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } on GoogleSignInException {
      // Nothing to do: the account is forgotten on our side regardless.
    }
  }

  /// The plugin's codes → ours. Android reports "no account on the device"
  /// as `unknownError` with a "No credential available" description.
  static GoogleIdTokenException mapException(GoogleSignInException e) {
    final message = e.description ?? e.code.name;
    final code = switch (e.code) {
      GoogleSignInExceptionCode.canceled => GoogleIdTokenFailure.cancelled,
      GoogleSignInExceptionCode.uiUnavailable ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        GoogleIdTokenFailure.unavailable,
      GoogleSignInExceptionCode.clientConfigurationError =>
        GoogleIdTokenFailure.misconfigured,
      GoogleSignInExceptionCode.unknownError
          when message.startsWith('No credential available') =>
        GoogleIdTokenFailure.noAccount,
      _ => GoogleIdTokenFailure.unknown,
    };
    return GoogleIdTokenException(code, message);
  }

  static const _nonceChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// A random URL-safe string from a secure generator.
  static String generateNonce([int length = 32]) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _nonceChars[random.nextInt(_nonceChars.length)],
    ).join();
  }

  static String sha256Hex(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}
