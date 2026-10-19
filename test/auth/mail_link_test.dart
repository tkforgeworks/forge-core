import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

const _redirect = 'https://example.com/apps/demo/auth/';
const _link = '$_redirect?token_hash=pkce_abc123&type=signup';
const _reset = '$_redirect?token_hash=pkce_def456&type=recovery';

Map<String, dynamic> _user() => {
  'id': 'user-1',
  'aud': 'authenticated',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T08:30:00Z',
  'email': 'tim@example.com',
  'email_confirmed_at': '2026-10-18T12:00:00Z',
  'identities': <Map<String, dynamic>>[],
};

Map<String, dynamic> _session() => {
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': _user(),
};

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

  SupabaseForgeAuth auth(
    (int, Object) Function(http.Request request) handler, {
    Stream<Uri>? links,
  }) {
    final a = SupabaseForgeAuth(
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
      emailRedirectUrl: _redirect,
      links: links,
    );
    addTearDown(a.dispose);
    return a;
  }

  Map<String, dynamic> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, dynamic>;

  /// Collects every state [a] emits from now on (after the initial one).
  Future<List<ForgeAuthState>> watch(SupabaseForgeAuth a) async {
    final states = <ForgeAuthState>[];
    final sub = a.changes.skip(1).listen(states.add);
    addTearDown(sub.cancel);
    await Future<void>.delayed(Duration.zero);
    return states;
  }

  group('ForgeMailLink.parse', () {
    test('reads the token and type the templates append', () {
      final mail = ForgeMailLink.parse(Uri.parse(_link));
      expect(
        mail,
        const ForgeMailLink(tokenHash: 'pkce_abc123', type: 'signup'),
      );
      expect(mail!.isPasswordReset, isFalse);
      expect(ForgeMailLink.parse(Uri.parse(_reset))!.isPasswordReset, isTrue);
    });

    test('is null for anything else', () {
      expect(ForgeMailLink.parse(Uri.parse(_redirect)), isNull);
      expect(ForgeMailLink.parse(Uri.parse('$_redirect?code=abc')), isNull);
      expect(
        ForgeMailLink.parse(Uri.parse('$_redirect?token_hash=&type=signup')),
        isNull,
      );
      expect(ForgeMailLink.parse(Uri.parse('$_redirect?token_hash=x')), isNull);
    });
  });

  group('handleLink', () {
    test('verifies a confirmation token and signs in', () async {
      final a = auth((_) => (200, _session()));
      final states = await watch(a);
      final result = await a.handleLink(Uri.parse(_link));
      expect(result, isA<ForgeAuthSuccess>());
      final r = requests.single;
      expect(r.method, 'POST');
      expect(r.url.path, endsWith('/verify'));
      expect(body(r)['token_hash'], 'pkce_abc123');
      expect(body(r)['type'], 'signup');
      expect(body(r).containsKey('email'), isFalse);
      expect(a.current.isSignedIn, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.event), [ForgeAuthEvent.signedIn]);
    });

    test('a reset token yields the password-recovery state', () async {
      final a = auth((_) => (200, _session()));
      final states = await watch(a);
      await a.handleLink(Uri.parse(_reset));
      expect(body(requests.single)['type'], 'recovery');
      await Future<void>.delayed(Duration.zero);
      expect(states.single.isPasswordRecovery, isTrue);
      expect(states.single.session?.email, 'tim@example.com');
    });

    test('an expired or used token fails and reaches the stream', () async {
      final a = auth(
        (_) => (
          403,
          {
            'error_code': 'otp_expired',
            'msg': 'Email link is invalid or has expired',
          },
        ),
      );
      final states = await watch(a);
      final result = await a.handleLink(Uri.parse(_link));
      expect((result as ForgeAuthFailure).error, ForgeAuthError.linkExpired);
      expect(a.current.isSignedIn, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(states.single.event, ForgeAuthEvent.mailLinkFailed);
      expect(states.single.isMailLinkFailed, isTrue);
      expect(states.single.error, ForgeAuthError.linkExpired);
      expect(states.single.session, isNull);
    });

    test('a link without a token is not ours: null, no request', () async {
      final a = auth((_) => (200, _session()));
      expect(await a.handleLink(Uri.parse('$_redirect?code=abc')), isNull);
      expect(await a.handleLink(Uri.parse('https://example.com/')), isNull);
      expect(requests, isEmpty);
    });

    test('an unknown type is refused before any request', () async {
      final a = auth((_) => (200, _session()));
      final states = await watch(a);
      final result = await a.handleLink(
        Uri.parse('$_redirect?token_hash=x&type=carrier_pigeon'),
      );
      expect((result as ForgeAuthFailure).error, ForgeAuthError.unknown);
      expect(requests, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(states.single.event, ForgeAuthEvent.mailLinkFailed);
    });
  });

  test('every mail link on the links stream is completed once', () async {
    final links = StreamController<Uri>();
    addTearDown(links.close);
    final a = auth((_) => (200, _session()), links: links.stream);
    final states = await watch(a);
    links.add(Uri.parse('https://example.com/'));
    links.add(Uri.parse(_link));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(requests.length, 1);
    expect(body(requests.single)['token_hash'], 'pkce_abc123');
    expect(states.map((s) => s.event), [ForgeAuthEvent.signedIn]);
  });
}
