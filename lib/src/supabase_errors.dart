import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'forge_result.dart';

/// Signals from inside a data call that the guard turns into results.
class ForgeDataException implements Exception {
  const ForgeDataException(this.error, this.message);
  final ForgeDataError error;
  final String message;
}

/// Runs a Supabase data call and turns anything it throws into a
/// [ForgeFailed]; a normal return becomes [ForgeOk].
Future<ForgeResult<T>> forgeGuard<T>(Future<T> Function() body) async {
  try {
    return ForgeOk(await body());
  } on ForgeDataException catch (e) {
    return ForgeFailed(e.error, e.message);
  } on sb.PostgrestException catch (e) {
    return ForgeFailed(forgeDataErrorOf(e), e.message);
  } on SocketException catch (e) {
    return ForgeFailed(ForgeDataError.network, e.message);
  } on TimeoutException catch (e) {
    return ForgeFailed(ForgeDataError.network, e.message ?? 'timed out');
  }
}

/// PostgREST / Postgres errors → ours. `28000` is the functions' "not signed
/// in"; `22001` / `23514` / `22P02` are the server refusing a value; `42501`
/// is RLS refusing a write, which for a signed-in user means the account is
/// pending deletion.
ForgeDataError forgeDataErrorOf(sb.PostgrestException e) => switch (e.code) {
  '28000' || 'PGRST301' || 'PGRST302' => ForgeDataError.sessionMissing,
  '22001' || '23514' || '22P02' || '23502' => ForgeDataError.invalid,
  '42501' => ForgeDataError.accountInactive,
  _ => ForgeDataError.unknown,
};
