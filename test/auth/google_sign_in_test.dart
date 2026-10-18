import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:forge_core/src/auth/google_id_token_source.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// A token source a test scripts: hand back a token, or throw.
class _FakeGoogle implements GoogleIdTokenSource {
  _FakeGoogle({this.token, this.failure});
  final GoogleIdToken? token;
  final GoogleIdTokenException? failure;
  var signOuts = 0;

  @override
  Future<GoogleIdToken> idToken() async {
    if (failure != null) throw failure!;
    return token!;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

Map<String, dynamic> _sessionJson() => {
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': {
    'id': 'user-1',
    'aud': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-10-01T08:30:00Z',
    'email': 'tim@example.com',
    'email_confirmed_at': '2026-10-18T12:00:00Z',
    'identities': [
      {
        'id': 'id-google',
        'user_id': 'user-1',
        'identity_id': 'iid',
        'provider': 'google',
        'identity_data': {'email': 'tim@example.com'},
      },
    ],
  },
};

void main() {
  group('PluginGoogleIdTokenSource.mapException', () {
    GoogleIdTokenFailure map(GoogleSignInExceptionCode code, [String? d]) =>
        PluginGoogleIdTokenSource.mapException(
          GoogleSignInException(code: code, description: d),
        ).code;

    test('maps the plugin codes, including Android\'s no-credential case', () {
      expect(
        map(GoogleSignInExceptionCode.canceled),
        GoogleIdTokenFailure.cancelled,
      );
      expect(
        map(GoogleSignInExceptionCode.uiUnavailable),
        GoogleIdTokenFailure.unavailable,
      );
      expect(
        map(GoogleSignInExceptionCode.providerConfigurationError),
        GoogleIdTokenFailure.unavailable,
      );
      expect(
        map(GoogleSignInExceptionCode.clientConfigurationError),
        GoogleIdTokenFailure.misconfigured,
      );
      expect(
        map(
          GoogleSignInExceptionCode.unknownError,
          'No credential available: none',
        ),
        GoogleIdTokenFailure.noAccount,
      );
      expect(
        map(GoogleSignInExceptionCode.unknownError, 'boom'),
        GoogleIdTokenFailure.unknown,
      );
      expect(
        map(GoogleSignInExceptionCode.interrupted),
        GoogleIdTokenFailure.unknown,
      );
    });

    test('nonces are random, URL-safe and hashed as SHA-256 hex', () {
      final a = PluginGoogleIdTokenSource.generateNonce();
      final b = PluginGoogleIdTokenSource.generateNonce();
      expect(a.length, 32);
      expect(a, isNot(b));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a), isTrue);
      expect(
        PluginGoogleIdTokenSource.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('SupabaseForgeAuth.signInWithGoogle', () {
    http.Request? captured;
    setUp(() => captured = null);
    sb.GoTrueClient client({int status = 200, Object? body}) => sb.GoTrueClient(
      url: 'https://abc.supabase.co/auth/v1',
      autoRefreshToken: false,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(body ?? _sessionJson()),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    test('exchanges the ID token and nonce for a session', () async {
      final auth = SupabaseForgeAuth(
        client(),
        google: _FakeGoogle(
          token: const GoogleIdToken('id.token', rawNonce: 'raw-nonce'),
        ),
      );
      final result = await auth.signInWithGoogle();
      expect(result, isA<ForgeAuthSuccess>());
      final session = (result as ForgeAuthSuccess).session;
      expect(session.userId, 'user-1');
      expect(session.has(ForgeIdentityProvider.google), isTrue);
      expect(captured!.url.path, endsWith('/token'));
      expect(captured!.url.queryParameters['grant_type'], 'id_token');
      final sent = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(sent['provider'], 'google');
      expect(sent['id_token'], 'id.token');
      expect(sent['nonce'], 'raw-nonce');
      expect(auth.current.isSignedIn, isTrue);
    });

    test('a cancelled picker is a cancellation, not an error', () async {
      final auth = SupabaseForgeAuth(
        client(),
        google: _FakeGoogle(
          failure: const GoogleIdTokenException(
            GoogleIdTokenFailure.cancelled,
            'canceled',
          ),
        ),
      );
      expect(await auth.signInWithGoogle(), const ForgeAuthCancelled());
      expect(captured, isNull);
    });

    test('plugin failures map to typed errors', () async {
      Future<ForgeAuthResult> run(GoogleIdTokenFailure code) =>
          SupabaseForgeAuth(
            client(),
            google: _FakeGoogle(
              failure: GoogleIdTokenException(code, code.name),
            ),
          ).signInWithGoogle();
      expect(
        await run(GoogleIdTokenFailure.noAccount),
        const ForgeAuthFailure(ForgeAuthError.noGoogleAccount, 'noAccount'),
      );
      expect(
        await run(GoogleIdTokenFailure.unavailable),
        const ForgeAuthFailure(ForgeAuthError.googleUnavailable, 'unavailable'),
      );
      expect(
        await run(GoogleIdTokenFailure.misconfigured),
        const ForgeAuthFailure(ForgeAuthError.misconfigured, 'misconfigured'),
      );
      expect(
        await run(GoogleIdTokenFailure.unknown),
        const ForgeAuthFailure(ForgeAuthError.unknown, 'unknown'),
      );
    });

    test('a backend rejection is a failure with the backend message', () async {
      final auth = SupabaseForgeAuth(
        client(
          status: 400,
          body: {'error_code': 'bad_id_token', 'msg': 'Bad ID token'},
        ),
        google: _FakeGoogle(token: const GoogleIdToken('bad')),
      );
      final result = await auth.signInWithGoogle();
      expect(result, isA<ForgeAuthFailure>());
      expect((result as ForgeAuthFailure).error, ForgeAuthError.unknown);
      expect(result.message, contains('Bad ID token'));
      expect(auth.current.isSignedIn, isFalse);
    });

    test('no web client ID means misconfigured, before any UI', () async {
      final result = await SupabaseForgeAuth(client()).signInWithGoogle();
      expect(result, isA<ForgeAuthFailure>());
      expect((result as ForgeAuthFailure).error, ForgeAuthError.misconfigured);
      expect(captured, isNull);
    });

    test('sign-out also forgets the Google account', () async {
      final google = _FakeGoogle(token: const GoogleIdToken('id.token'));
      final auth = SupabaseForgeAuth(client(), google: google);
      await auth.signInWithGoogle();
      await auth.signOut();
      expect(google.signOuts, 1);
    });

    test('retryable fetch errors are network errors', () {
      expect(
        SupabaseForgeAuth.mapAuthException(
          sb.AuthRetryableFetchException(message: 'offline'),
        ),
        ForgeAuthError.network,
      );
      expect(
        SupabaseForgeAuth.mapAuthException(const sb.AuthException('nope')),
        ForgeAuthError.unknown,
      );
    });
  });
}
