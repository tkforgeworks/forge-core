import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../auth/forge_auth.dart';
import '../forge_result.dart';
import '../supabase_errors.dart';
import 'forge_entry.dart';

/// A typed view of one `kind` in an app's `entries` table, with the calls
/// an app-side sync engine needs and nothing else. Every call returns a
/// [ForgeResult] and never throws; nothing runs when nobody is signed in.
///
/// The recommended sync (cheesy-scribe 0.3.0): push dirty rows with
/// [upsertAll] and local deletions with [markDeleted]; [listKeys] since the
/// last sync; [fetchByIds] the ones newer than the local copy; apply; store
/// the high-water mark. Last write wins per row on `updatedAt`.
abstract class ForgeEntriesRepository<T> {
  /// Inserts or replaces rows by id, keeping the client's `id` and
  /// `updatedAt`. Chunked; the server's `created_at` is kept on replace.
  Future<ForgeResult<void>> upsertAll(Iterable<ForgeEntry<T>> entries);

  /// Every row of this kind changed after [since] (all rows when null),
  /// oldest change first, paged internally.
  Future<ForgeResult<List<ForgeEntryKey>>> listKeys({DateTime? since});

  /// Full rows for [ids], chunked. Tombstones come back with null data.
  Future<ForgeResult<List<ForgeEntry<T>>>> fetchByIds(Iterable<String> ids);

  /// Records deletions: each id becomes a tombstone stamped [at] (data `{}`),
  /// created if the row never reached the server.
  Future<ForgeResult<void>> markDeleted(Iterable<String> ids, DateTime at);
}

/// [ForgeEntriesRepository] over a Supabase client.
class SupabaseForgeEntriesRepository<T> implements ForgeEntriesRepository<T> {
  SupabaseForgeEntriesRepository(
    this._client,
    this._auth, {
    required this.kind,
    required this.fromJson,
    required this.toJson,
    this.table = 'entries',
    this.pageSize = 500,
    this.chunkSize = 200,
  });

  final sb.SupabaseClient _client;
  final ForgeAuth _auth;

  /// The `kind` column value this repository owns.
  final String kind;
  final T Function(Map<String, dynamic> json) fromJson;
  final Map<String, dynamic> Function(T value) toJson;
  final String table;

  /// Rows per [listKeys] page.
  final int pageSize;

  /// Rows per upsert / ids per fetch request.
  final int chunkSize;

  String get _userId {
    final id = _auth.current.session?.userId;
    if (id == null) {
      throw const ForgeDataException(
        ForgeDataError.sessionMissing,
        'Not signed in',
      );
    }
    return id;
  }

  @override
  Future<ForgeResult<void>> upsertAll(Iterable<ForgeEntry<T>> entries) =>
      forgeGuard(() async {
        final userId = _userId;
        final rows = [for (final e in entries) _row(e, userId)];
        for (final chunk in _chunks(rows, chunkSize)) {
          await _client.from(table).upsert(chunk, onConflict: 'id');
        }
      });

  @override
  Future<ForgeResult<List<ForgeEntryKey>>> listKeys({DateTime? since}) =>
      forgeGuard(() async {
        final userId = _userId;
        final keys = <ForgeEntryKey>[];
        var offset = 0;
        while (true) {
          var query = _client
              .from(table)
              .select('id, updated_at, deleted_at')
              .eq('user_id', userId)
              .eq('kind', kind);
          if (since != null) {
            query = query.gt('updated_at', since.toUtc().toIso8601String());
          }
          final page = await query
              .order('updated_at', ascending: true)
              .order('id', ascending: true)
              .range(offset, offset + pageSize - 1);
          keys.addAll(page.map(ForgeEntryKey.fromJson));
          if (page.length < pageSize) return keys;
          offset += pageSize;
        }
      });

  @override
  Future<ForgeResult<List<ForgeEntry<T>>>> fetchByIds(Iterable<String> ids) =>
      forgeGuard(() async {
        final userId = _userId;
        final out = <ForgeEntry<T>>[];
        for (final chunk in _chunks(ids.toList(), chunkSize)) {
          final rows = await _client
              .from(table)
              .select()
              .eq('user_id', userId)
              .eq('kind', kind)
              .inFilter('id', chunk);
          out.addAll(rows.map(_entry));
        }
        return out;
      });

  @override
  Future<ForgeResult<void>> markDeleted(Iterable<String> ids, DateTime at) =>
      forgeGuard(() async {
        final userId = _userId;
        final stamp = at.toUtc().toIso8601String();
        final rows = [
          for (final id in ids)
            {
              'id': id,
              'user_id': userId,
              'kind': kind,
              'data': const <String, dynamic>{},
              'updated_at': stamp,
              'deleted_at': stamp,
            },
        ];
        for (final chunk in _chunks(rows, chunkSize)) {
          await _client.from(table).upsert(chunk, onConflict: 'id');
        }
      });

  Map<String, dynamic> _row(ForgeEntry<T> e, String userId) => {
    'id': e.id,
    'user_id': userId,
    'kind': kind,
    'data': e.isDeleted || e.data == null
        ? const <String, dynamic>{}
        : toJson(e.data as T),
    'updated_at': e.updatedAt.toUtc().toIso8601String(),
    'deleted_at': e.deletedAt?.toUtc().toIso8601String(),
  };

  ForgeEntry<T> _entry(Map<String, dynamic> row) {
    final deletedAt = row['deleted_at'] as String?;
    final data = row['data'] as Map<String, dynamic>?;
    return ForgeEntry<T>(
      id: row['id'] as String,
      data: deletedAt != null || data == null || data.isEmpty
          ? null
          : fromJson(data),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      createdAt: row['created_at'] == null
          ? null
          : DateTime.parse(row['created_at'] as String).toUtc(),
      deletedAt: deletedAt == null ? null : DateTime.parse(deletedAt).toUtc(),
    );
  }

  static Iterable<List<E>> _chunks<E>(List<E> items, int size) sync* {
    for (var i = 0; i < items.length; i += size) {
      yield items.sublist(i, i + size > items.length ? items.length : i + size);
    }
  }
}
