import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class _FakeGoogle implements GoogleIdTokenSource {
  _FakeGoogle({this.token, this.failure});
  final GoogleIdToken? token;
  final GoogleIdTokenException? failure;

  @override
  Future<GoogleIdToken> idToken() async {
    if (failure != null) throw failure!;
    return token!;
  }

  @override
  Future<void> signOut() async {}
}

Map<String, dynamic> _identity(String provider, {String? email}) => {
  'id': 'id-$provider',
  'user_id': 'user-1',
  'identity_id': 'link-$provider',
  'provider': provider,
  'identity_data': {'email': ?email},
};

Map<String, dynamic> _user(List<Map<String, dynamic>> identities) => {
  'id': 'user-1',
  'aud': 'authenticated',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T08:30:00Z',
  'email': 'tim@example.com',
  'email_confirmed_at': '2026-10-18T12:00:00Z',
  'identities': identities,
};

Map<String, dynamic> _session(List<Map<String, dynamic>> identities) => {
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': _user(identities),
};

void main() {
  late List<http.Request> requests;
  setUp(() => requests = []);

  SupabaseForgeAuth auth(
    (int, Object) Function(http.Request request) handler, {
    GoogleIdTokenSource? google,
  }) => SupabaseForgeAuth(
    sb.GoTrueClient(
      url: 'https://abc.supabase.co/auth/v1',
      autoRefreshToken: false,
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
    google: google,
  );

  final emailOnly = [_identity('email', email: 'tim@example.com')];
  final both = [
    _identity('email', email: 'tim@example.com'),
    _identity('google', email: 'tim@gmail.example'),
  ];

  group('linkGoogle', () {
    test('needs a session first, before showing any picker', () async {
      final r = await auth(
        (_) => (200, _session(both)),
        google: _FakeGoogle(token: const GoogleIdToken('t')),
      ).linkGoogle();
      expect((r as ForgeAuthFailure).error, ForgeAuthError.sessionMissing);
      expect(requests, isEmpty);
    });

    test('posts the ID token as a link on the current session', () async {
      final a = auth(
        (r) => r.url.queryParameters['grant_type'] == 'password'
            ? (200, _session(emailOnly))
            : (200, _session(both)),
        google: _FakeGoogle(
          token: const GoogleIdToken('id.token', rawNonce: 'raw'),
        ),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      final r = await a.linkGoogle();
      expect(r, isA<ForgeAuthSuccess>());
      expect(
        (r as ForgeAuthSuccess).session.has(ForgeIdentityProvider.google),
        isTrue,
      );
      final link = requests.last;
      expect(link.url.queryParameters['grant_type'], 'id_token');
      expect(link.headers['Authorization'], 'Bearer access');
      final body = jsonDecode(link.body) as Map<String, dynamic>;
      expect(body['link_identity'], isTrue);
      expect(body['id_token'], 'id.token');
      expect(body['nonce'], 'raw');
      expect(a.current.session!.identities, hasLength(2));
    });

    test(
      'a Google account that belongs to someone else, and manual linking off',
      () async {
        Future<ForgeAuthResult> run(String code) async {
          final a = auth(
            (r) => r.url.queryParameters['grant_type'] == 'password'
                ? (200, _session(emailOnly))
                : (400, {'error_code': code, 'msg': code}),
            google: _FakeGoogle(token: const GoogleIdToken('t')),
          );
          await a.signInWithEmail('tim@example.com', 'hunter22');
          return a.linkGoogle();
        }

        expect(
          ((await run('identity_already_exists')) as ForgeAuthFailure).error,
          ForgeAuthError.identityAlreadyLinked,
        );
        expect(
          ((await run('manual_linking_disabled')) as ForgeAuthFailure).error,
          ForgeAuthError.misconfigured,
        );
      },
    );

    test('a cancelled picker is a cancellation', () async {
      final a = auth(
        (_) => (200, _session(emailOnly)),
        google: _FakeGoogle(
          failure: const GoogleIdTokenException(
            GoogleIdTokenFailure.cancelled,
            'canceled',
          ),
        ),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      expect(await a.linkGoogle(), const ForgeAuthCancelled());
    });
  });

  group('unlinkIdentity', () {
    test(
      'refuses to remove the only sign-in method without a request',
      () async {
        final a = auth((_) => (200, _session(emailOnly)));
        await a.signInWithEmail('tim@example.com', 'hunter22');
        requests.clear();
        final r = await a.unlinkIdentity(a.current.session!.identities.single);
        expect((r as ForgeAuthFailure).error, ForgeAuthError.lastSignInMethod);
        expect(requests, isEmpty);
      },
    );

    test('deletes the identity and returns the refreshed account', () async {
      final a = auth(
        (r) => switch (r.method) {
          'DELETE' => (200, <String, dynamic>{}),
          'GET' => (200, _user(emailOnly)),
          _ => (200, _session(both)),
        },
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      final google = a.current.session!.identities.firstWhere(
        (i) => i.provider == ForgeIdentityProvider.google,
      );
      final r = await a.unlinkIdentity(google);
      expect(r, isA<ForgeAuthSuccess>());
      expect((r as ForgeAuthSuccess).session.identities, hasLength(1));
      final delete = requests.firstWhere((r) => r.method == 'DELETE');
      expect(delete.url.path, endsWith('/user/identities/link-google'));
      expect(delete.headers['Authorization'], 'Bearer access');
    });

    test('the server can still refuse (email conflict)', () async {
      final a = auth(
        (r) => r.method == 'DELETE'
            ? (
                400,
                {
                  'error_code': 'email_conflict_identity_not_deletable',
                  'msg': 'conflict',
                },
              )
            : (200, _session(both)),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      final r = await a.unlinkIdentity(a.current.session!.identities.last);
      expect((r as ForgeAuthFailure).error, ForgeAuthError.lastSignInMethod);
    });
  });

  test(
    'setPassword is updatePassword under the account page\'s name',
    () async {
      final a = auth(
        (r) => r.method == 'PUT' ? (200, _user(both)) : (200, _session(both)),
      );
      await a.signInWithEmail('tim@example.com', 'hunter22');
      expect(await a.setPassword('newpassword1'), isA<ForgeAuthSuccess>());
      final put = requests.last;
      expect(put.method, 'PUT');
      expect((jsonDecode(put.body) as Map)['password'], 'newpassword1');
    },
  );
}
