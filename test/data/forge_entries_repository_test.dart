import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'repository_access.dart';

/// The app's type for the tests: a note with a name.
class Note {
  const Note(this.name);
  final String name;
  Map<String, dynamic> toJson() => {'name': name};
  static Note fromJson(Map<String, dynamic> j) => Note(j['name'] as String);

  @override
  bool operator ==(Object other) => other is Note && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

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
    'identities': <Map<String, dynamic>>[],
  },
};

Map<String, dynamic> _row(
  String id,
  String updatedAt, {
  String? name,
  String? deletedAt,
}) => {
  'id': id,
  'user_id': 'user-1',
  'kind': 'tasting_note',
  'data': name == null ? <String, dynamic>{} : {'name': name},
  'created_at': '2026-10-01T00:00:00Z',
  'updated_at': updatedAt,
  'deleted_at': deletedAt,
};

void main() {
  late List<http.Request> requests;
  late Object Function(http.Request) restReply;
  setUp(() {
    requests = [];
    restReply = (_) => <Map<String, dynamic>>[];
  });

  Future<(ForgeCore, ForgeEntriesRepository<Note>)> core({
    int pageSize = 500,
    int chunkSize = 200,
  }) async {
    const config = ForgeSupabaseConfig(
      url: 'https://abc.supabase.co',
      publishableKey: 'sb_publishable_x',
    );
    final client = sb.SupabaseClient(
      config.url,
      config.publishableKey,
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        final Object body = path.endsWith('/auth/v1/token')
            ? _session()
            : restReply(request);
        return http.Response(
          jsonEncode(body),
          path.endsWith('/auth/v1/token') ? 200 : 200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final c = ForgeCore.withClient(client, config);
    addTearDown(c.dispose);
    final repo = SupabaseForgeEntriesRepositoryForTest.create(
      c,
      pageSize: pageSize,
      chunkSize: chunkSize,
    );
    await c.auth.signInWithEmail('tim@example.com', 'hunter22');
    requests.clear();
    return (c, repo);
  }

  Iterable<http.Request> rest() =>
      requests.where((r) => r.url.path.contains('/rest/v1/entries'));

  test('nothing runs when nobody is signed in', () async {
    const config = ForgeSupabaseConfig(
      url: 'https://abc.supabase.co',
      publishableKey: 'k',
    );
    final c = ForgeCore.withClient(
      sb.SupabaseClient(
        config.url,
        config.publishableKey,
        httpClient: MockClient((r) async {
          requests.add(r);
          return http.Response('[]', 200, request: r);
        }),
      ),
      config,
    );
    addTearDown(c.dispose);
    final repo = c.entries<Note>(
      kind: 'tasting_note',
      fromJson: Note.fromJson,
      toJson: (n) => n.toJson(),
    );
    expect((await repo.listKeys()), isA<ForgeFailed<List<ForgeEntryKey>>>());
    expect(
      ((await repo.upsertAll([])) as ForgeFailed).error,
      ForgeDataError.sessionMissing,
    );
    expect(requests, isEmpty);
  });

  test(
    'upsertAll sends client ids and stamps, merging on id, in chunks',
    () async {
      final (_, repo) = await core(chunkSize: 2);
      final at = DateTime.utc(2026, 10, 18, 12);
      final result = await repo.upsertAll([
        ForgeEntry(id: 'a', data: const Note('Comté'), updatedAt: at),
        ForgeEntry(id: 'b', data: const Note('Brie'), updatedAt: at),
        ForgeEntry(id: 'c', data: null, updatedAt: at, deletedAt: at),
      ]);
      expect(result, const ForgeOk<void>(null));
      final posts = rest().where((r) => r.method == 'POST').toList();
      expect(posts, hasLength(2)); // chunks of 2
      expect(posts.first.url.queryParameters['on_conflict'], 'id');
      expect(
        posts.first.headers['Prefer'],
        contains('resolution=merge-duplicates'),
      );
      expect(posts.first.headers['Authorization'], 'Bearer access');
      final rows = jsonDecode(posts.first.body) as List;
      expect(rows.first, {
        'id': 'a',
        'user_id': 'user-1',
        'kind': 'tasting_note',
        'data': {'name': 'Comté'},
        'updated_at': '2026-10-18T12:00:00.000Z',
        'deleted_at': null,
      });
      final tombstone = (jsonDecode(posts.last.body) as List).single as Map;
      expect(tombstone['data'], <String, dynamic>{});
      expect(tombstone['deleted_at'], '2026-10-18T12:00:00.000Z');
    },
  );

  test('listKeys filters by user, kind and since; orders; pages', () async {
    final (_, repo) = await core(pageSize: 2);
    var call = 0;
    restReply = (r) {
      call++;
      return call == 1
          ? [
              _row('a', '2026-10-18T10:00:00Z'),
              _row('b', '2026-10-18T11:00:00Z'),
            ]
          : [
              _row(
                'c',
                '2026-10-18T12:00:00Z',
                deletedAt: '2026-10-18T12:00:00Z',
              ),
            ];
    };
    final result = await repo.listKeys(since: DateTime.utc(2026, 10, 18, 9));
    final keys = (result as ForgeOk<List<ForgeEntryKey>>).value;
    expect(keys.map((k) => k.id), ['a', 'b', 'c']);
    expect(keys.last.isDeleted, isTrue);
    expect(keys.first.updatedAt, DateTime.utc(2026, 10, 18, 10));
    final gets = rest().toList();
    expect(gets, hasLength(2));
    final q = gets.first.url.queryParameters;
    expect(q['select'], 'id,updated_at,deleted_at');
    expect(q['user_id'], 'eq.user-1');
    expect(q['kind'], 'eq.tasting_note');
    expect(q['updated_at'], 'gt.2026-10-18T09:00:00.000Z');
    expect(q['order'], 'updated_at.asc.nullslast,id.asc.nullslast');
    expect((q['offset'], q['limit']), ('0', '2'));
    final q2 = gets.last.url.queryParameters;
    expect((q2['offset'], q2['limit']), ('2', '2'));
    expect(gets.last.url.queryParameters.containsKey('updated_at'), isTrue);
  });

  test('listKeys without since lists everything', () async {
    final (_, repo) = await core();
    await repo.listKeys();
    expect(
      rest().single.url.queryParameters.containsKey('updated_at'),
      isFalse,
    );
  });

  test('fetchByIds chunks the id filter and types the rows', () async {
    final (_, repo) = await core(chunkSize: 2);
    restReply = (r) {
      final ids = r.url.queryParameters['id']!; // in.("a","b")
      return [
        for (final id
            in ids
                .substring(4, ids.length - 1)
                .split(',')
                .map((v) => v.replaceAll('"', '')))
          if (id == 'c')
            _row(id, '2026-10-18T12:00:00Z', deletedAt: '2026-10-18T12:00:00Z')
          else
            _row(id, '2026-10-18T10:00:00Z', name: 'Note $id'),
      ];
    };
    final result = await repo.fetchByIds(['a', 'b', 'c']);
    final entries = (result as ForgeOk<List<ForgeEntry<Note>>>).value;
    expect(entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(entries.first.data, const Note('Note a'));
    expect(entries.first.createdAt, DateTime.utc(2026, 10, 1));
    expect(entries.last.data, isNull);
    expect(entries.last.isDeleted, isTrue);
    final gets = rest().toList();
    expect(gets, hasLength(2));
    expect(gets.first.url.queryParameters['id'], 'in.("a","b")');
    expect(gets.last.url.queryParameters['id'], 'in.("c")');
    expect(gets.first.url.queryParameters['kind'], 'eq.tasting_note');
  });

  test('markDeleted upserts tombstones stamped at the given time', () async {
    final (_, repo) = await core();
    final at = DateTime.utc(2026, 10, 18, 13);
    expect(await repo.markDeleted(['x', 'y'], at), const ForgeOk<void>(null));
    final post = rest().single;
    expect(post.method, 'POST');
    expect(post.url.queryParameters['on_conflict'], 'id');
    final rows = jsonDecode(post.body) as List;
    expect(rows, hasLength(2));
    expect(rows.first, {
      'id': 'x',
      'user_id': 'user-1',
      'kind': 'tasting_note',
      'data': <String, dynamic>{},
      'updated_at': '2026-10-18T13:00:00.000Z',
      'deleted_at': '2026-10-18T13:00:00.000Z',
    });
  });

  test('server errors become typed failures', () async {
    final (_, repo) = await core();
    restReply = (_) =>
        throw sb.PostgrestException(message: 'denied', code: '42501');
    // The mock throws inside the handler; MockClient surfaces it as the
    // request failing, which postgrest reports as PostgrestException.
    final result = await repo.listKeys();
    expect(result, isA<ForgeFailed<List<ForgeEntryKey>>>());
  });

  test('FakeForgeEntriesRepository plays the server for a sync test', () async {
    final auth = FakeForgeAuth();
    addTearDown(auth.dispose);
    final repo = FakeForgeEntriesRepository<Note>(auth);
    expect(
      ((await repo.listKeys()) as ForgeFailed).error,
      ForgeDataError.sessionMissing,
    );
    auth.signIn(FakeForgeAuth.fakeSession);
    final t1 = DateTime.utc(2026, 10, 18, 10);
    final t2 = DateTime.utc(2026, 10, 18, 11);
    await repo.upsertAll([
      ForgeEntry(id: 'a', data: const Note('Comté'), updatedAt: t1),
    ]);
    repo.remoteUpsert([
      ForgeEntry(id: 'b', data: const Note('Brie'), updatedAt: t2),
    ]);
    final keys = ((await repo.listKeys(
      since: t1,
    )) as ForgeOk<List<ForgeEntryKey>>).value;
    expect(keys.map((k) => k.id), ['b']);
    await repo.markDeleted(['a'], t2);
    final all = ((await repo.listKeys()) as ForgeOk<List<ForgeEntryKey>>).value;
    expect(all.map((k) => (k.id, k.isDeleted)), [('a', true), ('b', false)]);
    final fetched = ((await repo.fetchByIds([
      'a',
      'b',
      'zzz',
    ])) as ForgeOk<List<ForgeEntry<Note>>>).value;
    expect(fetched.map((e) => e.id), ['a', 'b']);
    expect(fetched.first.data, isNull);
    expect(repo.rows['a']!.createdAt, t1); // kept across the tombstone
    repo.nextError = ForgeDataError.network;
    expect(
      ((await repo.fetchByIds(['a'])) as ForgeFailed).error,
      ForgeDataError.network,
    );
    expect(
      repo.calls.map((c) => c.$1),
      containsAll(['listKeys', 'upsertAll', 'markDeleted', 'fetchByIds']),
    );
  });
}

/// Builds the repository with small page/chunk sizes for the tests.
extension SupabaseForgeEntriesRepositoryForTest on Never {
  static ForgeEntriesRepository<Note> create(
    ForgeCore core, {
    required int pageSize,
    required int chunkSize,
  }) => SupabaseForgeEntriesRepositoryAccess.build(core, pageSize, chunkSize);
}
