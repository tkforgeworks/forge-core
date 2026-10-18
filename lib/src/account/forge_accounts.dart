import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../auth/forge_auth.dart';
import '../forge_result.dart';
import '../supabase_errors.dart';
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

  /// Deletes the account: flags it for the purge (access ends at once) and
  /// signs out on every device. The server removes everything within the
  /// purge window; what happens to the app's local data is the app's call.
  Future<ForgeResult<void>> deleteAccount();

  static const maxUsernameLength = 40;
}

/// [ForgeAccounts] over a Supabase client.
class SupabaseForgeAccounts implements ForgeAccounts {
  SupabaseForgeAccounts(this._client, this._auth);

  final sb.SupabaseClient _client;
  final ForgeAuth _auth;

  @override
  Future<ForgeResult<ForgeAccount?>> getAccount() => forgeGuard(() async {
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
  Future<ForgeResult<void>> deleteAccount() => forgeGuard(() async {
    if (_auth.current.session == null) {
      throw const ForgeDataException(
        ForgeDataError.sessionMissing,
        'Not signed in',
      );
    }
    await _client.rpc<void>('request_account_deletion');
    await _auth.signOut(everywhere: true);
  });

  @override
  Future<ForgeResult<ForgeAccount>> setUsername(String? username) =>
      forgeGuard(() async {
        if (_auth.current.session == null) {
          throw const ForgeDataException(
            ForgeDataError.sessionMissing,
            'Not signed in',
          );
        }
        final trimmed = username?.trim() ?? '';
        if (trimmed.length > ForgeAccounts.maxUsernameLength) {
          throw const ForgeDataException(
            ForgeDataError.invalid,
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
          ForgeOk() => throw const ForgeDataException(
            ForgeDataError.unknown,
            'No account row for this user',
          ),
          ForgeFailed(:final error, :final message) => throw ForgeDataException(
            error,
            message,
          ),
        };
      });

  /// PostgREST / Postgres errors → ours (see `forgeDataErrorOf`).
  static ForgeDataError mapPostgrestException(sb.PostgrestException e) =>
      forgeDataErrorOf(e);
}
