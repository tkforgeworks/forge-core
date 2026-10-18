import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../auth/forge_auth.dart';
import '../forge_result.dart';
import 'forge_account.dart';

/// The signed-in user's account row: read it, watch it across sign-ins,
/// set the username. Deletion arrives in FC-9 on this same object.
///
/// Reads go through the row's select policy; writes go through the
/// security-definer functions the migration installs, never the table.
abstract class ForgeAccounts {
  /// The current user's row, or `ForgeOk(null)` when nobody is signed in.
  Future<ForgeResult<ForgeAccount?>> getAccount();

  /// Re-reads the row on every auth change, so the account page follows
  /// sign-in, sign-out and user updates. Emits once on listen.
  Stream<ForgeResult<ForgeAccount?>> watchAccount();

  /// Sets the username, or clears it with null or blank. Trimmed; at most
  /// [maxUsernameLength] characters.
  Future<ForgeResult<ForgeAccount>> setUsername(String? username);

  static const maxUsernameLength = 40;
}

/// [ForgeAccounts] over a Supabase client.
class SupabaseForgeAccounts implements ForgeAccounts {
  SupabaseForgeAccounts(this._client, this._auth);

  final sb.SupabaseClient _client;
  final ForgeAuth _auth;

  @override
  Future<ForgeResult<ForgeAccount?>> getAccount() => _guard(() async {
    final userId = _auth.current.session?.userId;
    if (userId == null) return null;
    final row = await _client
        .from('accounts')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : ForgeAccount.fromJson(row);
  });

  @override
  Stream<ForgeResult<ForgeAccount?>> watchAccount() =>
      _auth.changes.asyncMap((_) => getAccount());

  @override
  Future<ForgeResult<ForgeAccount>> setUsername(String? username) =>
      _guard(() async {
        if (_auth.current.session == null) {
          throw const _SessionMissing();
        }
        final trimmed = username?.trim() ?? '';
        if (trimmed.length > ForgeAccounts.maxUsernameLength) {
          throw const _Invalid(
            'Usernames are at most ${ForgeAccounts.maxUsernameLength} '
            'characters',
          );
        }
        await _client.rpc<void>(
          'set_username',
          params: {'new_username': trimmed.isEmpty ? null : trimmed},
        );
        final after = await getAccount();
        return switch (after) {
          ForgeOk(:final value) when value != null => value,
          ForgeOk() => throw const _Invalid('No account row for this user'),
          ForgeFailed(:final error, :final message) => throw _Rethrow(
            error,
            message,
          ),
        };
      });

  Future<ForgeResult<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return ForgeOk(await body());
    } on _SessionMissing {
      return const ForgeFailed(ForgeDataError.sessionMissing, 'Not signed in');
    } on _Invalid catch (e) {
      return ForgeFailed(ForgeDataError.invalid, e.message);
    } on _Rethrow catch (e) {
      return ForgeFailed(e.error, e.message);
    } on sb.PostgrestException catch (e) {
      return ForgeFailed(mapPostgrestException(e), e.message);
    } on SocketException catch (e) {
      return ForgeFailed(ForgeDataError.network, e.message);
    } on TimeoutException catch (e) {
      return ForgeFailed(ForgeDataError.network, e.message ?? 'timed out');
    }
  }

  /// PostgREST / Postgres errors → ours. `28000` is the functions' "not
  /// signed in"; `22001` their "too long"; `42501` is RLS refusing a write
  /// (which the functions never cause, but a stale token might).
  static ForgeDataError mapPostgrestException(sb.PostgrestException e) =>
      switch (e.code) {
        '28000' || 'PGRST301' || 'PGRST302' => ForgeDataError.sessionMissing,
        '22001' || '23514' || '22P02' => ForgeDataError.invalid,
        '42501' => ForgeDataError.accountInactive,
        _ => ForgeDataError.unknown,
      };
}

class _SessionMissing implements Exception {
  const _SessionMissing();
}

class _Invalid implements Exception {
  const _Invalid(this.message);
  final String message;
}

class _Rethrow implements Exception {
  const _Rethrow(this.error, this.message);
  final ForgeDataError error;
  final String message;
}
