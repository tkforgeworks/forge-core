import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _redirect = 'com.example.app://auth-callback';

Map<String, dynamic> _user({bool confirmed = true}) => {
  'id': 'user-1',
  'aud': 'authenticated',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T08:30:00Z',
  'email': 'tim@example.com',
  if (confirmed) 'email_confirmed_at': '2026-10-18T12:00:00Z',
  'identities': [
    {
      'id': 'id-email',
      'user_id': 'user-1',
      'identity_id': 'iid',
      'provider': 'email',
      'identity_data': {'email': 'tim@example.com'},
    },
  ],
};

Map<String, dynamic> _session() => {
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': _user(),
};

/// GoTrue's PKCE flow keeps its code verifier here between the request and
/// the callback; in an app supabase_flutter provides one over
/// SharedPreferences.
class _MemoryStorage extends sb.GotrueAsyncStorage {
  final _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

void main() {
  late List<http.Request> requests;
  setUp(() => requests = []);

  /// A GoTrue client whose server is [handler]: path → (status, body).
  SupabaseForgeAuth auth(
    (int, Object) Function(http.Request request) handler, {
    String redirect = _redirect,
  }) => SupabaseForgeAuth(
    sb.GoTrueClient(
      url: 'https://abc.supabase.co/auth/v1',
      autoRefreshToken: false,
      asyncStorage: _MemoryStorage(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final (status, body) = handler(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    ),
    emailRedirectUrl: redirect,
  );

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  (int, Object) error(String code, String msg) =>
      (400, {'error_code': code, 'msg': msg});

  group('signUpWithEmail', () {
    test('confirmation required: mail sent, no session yet', () async {
      final a = auth((r) => (200, _user(confirmed: false)));
      final result = await a.signUpWithEmail(' tim@example.com ', 'hunter22');
      expect(
        result,
        const ForgeAuthEmailSent(
          'tim@example.com',
          ForgeMailPurpose.confirmation,
        ),
      );
      final r = requests.single;
      expect(r.url.path, endsWith('/signup'));
      expect(r.url.queryParameters['redirect_to'], _redirect);
      expect(body(r)['email'], 'tim@example.com');
      expect(body(r)['password'], 'hunter22');
      expect(a.current.isSignedIn, isFalse);
    });

    test('autoconfirm projects sign straight in', () async {
      final a = auth((r) => (200, _session()));
      final result = await a.signUpWithEmail('tim@example.com', 'hunter22');
      expect(result, isA<ForgeAuthSuccess>());
      expect(a.current.isSignedIn, isTrue);
    });

    test('an existing address, a weak password, a bad address', () async {
      var r = await auth(
        (_) => error('user_already_exists', 'User already registered'),
      ).signUpWithEmail('tim@example.com', 'hunter22');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.emailTaken);

      r = await auth(
        (_) => (
          422,
          {
            'error_code': 'weak_password',
            'msg': 'Password is too weak',
            'weak_password': {
              'reasons': ['length', 'pwned'],
            },
          },
        ),
      ).signUpWithEmail('tim@example.com', 'short');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.weakPassword);
      expect(r.message, 'Password is too weak (length, pwned)');

      r = await auth(
        (_) => error('validation_failed', 'Unable to validate email address'),
      ).signUpWithEmail('nope', 'hunter22');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.invalidEmail);
    });
  });

  group('signInWithEmail', () {
    test('signs in with the password grant', () async {
      final a = auth((r) => (200, _session()));
      final result = await a.signInWithEmail('tim@example.com', 'hunter22');
      expect(result, isA<ForgeAuthSuccess>());
      expect(
        (result as ForgeAuthSuccess).session.has(ForgeIdentityProvider.email),
        isTrue,
      );
      final r = requests.single;
      expect(r.url.path, endsWith('/token'));
      expect(r.url.queryParameters['grant_type'], 'password');
      expect(a.current.isSignedIn, isTrue);
    });

    test('wrong password and unconfirmed account are told apart', () async {
      var r = await auth(
        (_) => error('invalid_credentials', 'Invalid login credentials'),
      ).signInWithEmail('tim@example.com', 'wrong');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.invalidCredentials);

      r = await auth((_) => error('email_not_confirmed', 'Email not confirmed'))
          .signInWithEmail('tim@example.com', 'hunter22');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.emailNotConfirmed);
    });
  });

  group('mail flows', () {
    test('resendConfirmation posts to /resend with the redirect', () async {
      final result = await auth((r) => (200, {'message_id': 'x'}))
          .resendConfirmation('tim@example.com');
      expect(
        result,
        const ForgeAuthEmailSent(
          'tim@example.com',
          ForgeMailPurpose.confirmation,
        ),
      );
      final r = requests.single;
      expect(r.url.path, endsWith('/resend'));
      expect(body(r)['type'], 'signup');
      expect(body(r)['email'], 'tim@example.com');
      expect(r.url.queryParameters['redirect_to'], _redirect);
    });

    test(
      'sendPasswordReset carries the redirect and a PKCE challenge',
      () async {
        final result = await auth((r) => (200, <String, dynamic>{}))
            .sendPasswordReset('tim@example.com');
        expect(
          result,
          const ForgeAuthEmailSent(
            'tim@example.com',
            ForgeMailPurpose.passwordReset,
          ),
        );
        final r = requests.single;
        expect(r.url.path, endsWith('/recover'));
        expect(r.url.queryParameters['redirect_to'], _redirect);
        expect(body(r)['email'], 'tim@example.com');
        expect(body(r)['code_challenge'], isNotNull);
      },
    );

    test('too many mails is rateLimited', () async {
      final r = await auth(
        (_) => (
          429,
          {'error_code': 'over_email_send_rate_limit', 'msg': 'slow down'},
        ),
      ).sendPasswordReset('tim@example.com');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.rateLimited);
    });

    test('no redirect configured sends none (Site URL applies)', () async {
      await auth(
        (r) => (200, <String, dynamic>{}),
        redirect: '',
      ).sendPasswordReset('tim@example.com');
      expect(
        requests.single.url.queryParameters.containsKey('redirect_to'),
        isFalse,
      );
    });
  });

  group('updatePassword', () {
    test('needs a session', () async {
      final r = await auth((_) => (200, _user()))
          .updatePassword('newpassword1');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.sessionMissing);
      expect(requests, isEmpty);
    });

    test('updates the signed-in user', () async {
      final a = auth(
        (r) =>
            r.url.path.endsWith('/user') ? (200, _user()) : (200, _session()),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      final r = await a.updatePassword('newpassword1');
      expect(r, isA<ForgeAuthSuccess>());
      final put = requests.last;
      expect(put.method, 'PUT');
      expect(put.url.path, endsWith('/user'));
      expect(body(put)['password'], 'newpassword1');
    });

    test('same password and an expired link map to their errors', () async {
      final a = auth(
        (r) => r.url.path.endsWith('/user')
            ? error('same_password', 'New password should be different')
            : (200, _session()),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      final r = await a.updatePassword('hunter22');
      expect((r as ForgeAuthFailure).error, ForgeAuthError.samePassword);
      expect(
        SupabaseForgeAuth.mapAuthException(
          const sb.AuthApiException('expired', code: 'otp_expired'),
        ),
        ForgeAuthError.linkExpired,
      );
      expect(
        SupabaseForgeAuth.mapAuthException(
          const sb.AuthApiException('off', code: 'signup_disabled'),
        ),
        ForgeAuthError.misconfigured,
      );
    });
  });
}
