import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/account/forge_accounts.dart';
import 'package:forge_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

Map<String, dynamic> _session() => {
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
    'identities': <Map<String, dynamic>>[],
  },
};

Map<String, dynamic> _row({String? username, String? deletedAt}) => {
  'id': 'user-1',
  'username': username,
  'created_at': '2026-10-01T08:30:00Z',
  'deletion_requested_at': deletedAt,
};

void main() {
  late List<http.Request> requests;
  late String? storedUsername;
  late (int, Object)? nextRpc;
  setUp(() {
    requests = [];
    storedUsername = null;
    nextRpc = null;
  });

  /// A client whose server signs anyone in and serves one account row.
  ForgeCore core() {
    final config = const ForgeSupabaseConfig(
      url: 'https://abc.supabase.co',
      publishableKey: 'sb_publishable_x',
    );
    final client = sb.SupabaseClient(
      config.url,
      config.publishableKey,
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        (int, Object) reply;
        if (path.endsWith('/auth/v1/token')) {
          reply = (200, _session());
        } else if (path.endsWith('/rest/v1/rpc/set_username')) {
          reply =
              nextRpc ??
              () {
                storedUsername =
                    (jsonDecode(request.body) as Map)['new_username']
                        as String?;
                return (204, '');
              }();
        } else if (path.endsWith('/rest/v1/accounts')) {
          reply = (200, _row(username: storedUsername));
        } else {
          reply = (404, {'message': 'no route $path'});
        }
        final (status, body) = reply;
        return http.Response(
          body is String ? body : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final core = ForgeCore.withClient(client, config);
    addTearDown(core.dispose);
    return core;
  }

  test('nobody signed in: no row, no request', () async {
    final c = core();
    expect(await c.accounts.getAccount(), const ForgeOk<ForgeAccount?>(null));
    expect(requests, isEmpty);
    expect(
      await c.accounts.setUsername('Tim'),
      const ForgeFailed<ForgeAccount>(
        ForgeDataError.sessionMissing,
        'Not signed in',
      ),
    );
    expect(requests, isEmpty);
  });

  test('reads the signed-in user\'s row through its select policy', () async {
    final c = core();
    await c.auth.signInWithEmail('tim@example.com', 'hunter22');
    final result = await c.accounts.getAccount();
    final account = (result as ForgeOk<ForgeAccount?>).value!;
    expect(account.userId, 'user-1');
    expect(account.username, isNull);
    expect(account.createdAt, DateTime.utc(2026, 10, 1, 8, 30));
    expect(account.isPendingDeletion, isFalse);
    final get = requests.last;
    expect(get.method, 'GET');
    expect(get.url.path, endsWith('/rest/v1/accounts'));
    expect(get.url.queryParameters['id'], 'eq.user-1');
    expect(get.headers['Authorization'], 'Bearer access');
  });

  test('setUsername trims, calls the function and re-reads', () async {
    final c = core();
    await c.auth.signInWithEmail('tim@example.com', 'hunter22');
    final result = await c.accounts.setUsername('  Tim  ');
    expect((result as ForgeOk<ForgeAccount>).value.username, 'Tim');
    final rpc = requests.firstWhere(
      (r) => r.url.path.endsWith('/rpc/set_username'),
    );
    expect(rpc.method, 'POST');
    expect(jsonDecode(rpc.body), {'new_username': 'Tim'});
    expect(rpc.headers['Authorization'], 'Bearer access');

    final cleared = await c.accounts.setUsername('   ');
    expect((cleared as ForgeOk<ForgeAccount>).value.username, isNull);
    expect(
      jsonDecode(
        requests
            .where((r) => r.url.path.endsWith('/rpc/set_username'))
            .last
            .body,
      ),
      {'new_username': null},
    );
  });

  test(
    'too long is refused locally; server errors map to typed ones',
    () async {
      final c = core();
      await c.auth.signInWithEmail('tim@example.com', 'hunter22');
      final tooLong = await c.accounts.setUsername('x' * 41);
      expect((tooLong as ForgeFailed).error, ForgeDataError.invalid);
      expect(
        requests.where((r) => r.url.path.endsWith('/rpc/set_username')),
        isEmpty,
      );

      nextRpc = (
        400,
        {'code': '22001', 'message': 'too long', 'details': null, 'hint': null},
      );
      final serverSide =
          await c.accounts.setUsername('fine') as ForgeFailed<ForgeAccount>;
      expect(serverSide.error, ForgeDataError.invalid);
      expect(serverSide.message, 'too long');

      nextRpc = (
        401,
        {
          'code': 'PGRST301',
          'message': 'JWT expired',
          'details': null,
          'hint': null,
        },
      );
      expect(
        ((await c.accounts.setUsername('fine')) as ForgeFailed).error,
        ForgeDataError.sessionMissing,
      );
    },
  );

  test('watchAccount re-reads on every auth change', () async {
    final c = core();
    final seen = <ForgeAccount?>[];
    final sub = c.accounts.watchAccount().listen(
      (r) => seen.add((r as ForgeOk<ForgeAccount?>).value),
    );
    await pumpEventQueue();
    await c.auth.signInWithEmail('tim@example.com', 'hunter22');
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, isNull);
    expect(seen.last?.userId, 'user-1');
  });

  test(
    'ForgeAccount parses deletion and FakeForgeAccounts behaves alike',
    () async {
      final pending = ForgeAccount.fromJson(
        _row(deletedAt: '2026-10-18T12:00:00Z'),
      );
      expect(pending.isPendingDeletion, isTrue);
      expect(pending.deletionRequestedAt, DateTime.utc(2026, 10, 18, 12));

      final auth = FakeForgeAuth();
      addTearDown(auth.dispose);
      final accounts = FakeForgeAccounts(auth);
      expect(await accounts.getAccount(), const ForgeOk<ForgeAccount?>(null));
      expect(
        ((await accounts.setUsername('Tim')) as ForgeFailed).error,
        ForgeDataError.sessionMissing,
      );
      auth.signIn(FakeForgeAuth.fakeSession);
      final set = await accounts.setUsername(' Tim ');
      expect((set as ForgeOk<ForgeAccount>).value.username, 'Tim');
      expect(
        ((await accounts.getAccount()) as ForgeOk<ForgeAccount?>)
            .value!
            .username,
        'Tim',
      );
      expect(accounts.usernameWrites, ['Tim', ' Tim ']);
      accounts.nextError = ForgeDataError.network;
      expect(
        ((await accounts.getAccount()) as ForgeFailed).error,
        ForgeDataError.network,
      );
      expect(
        await accounts.getAccount(),
        isA<ForgeOk<ForgeAccount?>>(),
      ); // one-shot
    },
  );

  test('mapPostgrestException', () {
    ForgeDataError map(String code) =>
        SupabaseForgeAccounts.mapPostgrestException(
          sb.PostgrestException(message: 'm', code: code),
        );
    expect(map('28000'), ForgeDataError.sessionMissing);
    expect(map('22001'), ForgeDataError.invalid);
    expect(map('23514'), ForgeDataError.invalid);
    expect(map('42501'), ForgeDataError.accountInactive);
    expect(map('XX000'), ForgeDataError.unknown);
  });
}
