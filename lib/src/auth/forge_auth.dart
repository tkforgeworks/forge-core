import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'forge_auth_result.dart';
import 'forge_session.dart';
import 'google_id_token_source.dart';

/// Session state, sign-in and sign-out, in plain types. Apps wrap [changes]
/// in their state layer (a Riverpod `StreamProvider`, say) and never touch
/// Supabase.
///
/// Email/password arrives in FC-5 on this same object. The production
/// implementation is [SupabaseForgeAuth]; `package:forge_core/testing.dart`
/// has a fake for app tests.
abstract class ForgeAuth {
  /// The state right now.
  ForgeAuthState get current;

  /// Emits [current] first, then every change. A broadcast stream: listen
  /// from as many places as you like.
  Stream<ForgeAuthState> get changes;

  /// Native Google sign-in: the account picker, then the ID token exchanged
  /// with Supabase. Never throws; every outcome is a [ForgeAuthResult].
  Future<ForgeAuthResult> signInWithGoogle();

  /// Ends the session on this device, or on every device with [everywhere]
  /// (account deletion uses that). Never touches the app's own storage.
  Future<void> signOut({bool everywhere = false});
}

/// [ForgeAuth] over a Supabase client. [google] is null when the build has
/// no web client ID, in which case [signInWithGoogle] reports
/// [ForgeAuthError.misconfigured].
class SupabaseForgeAuth implements ForgeAuth {
  SupabaseForgeAuth(this._auth, {this._google});

  final sb.GoTrueClient _auth;
  final GoogleIdTokenSource? _google;

  @override
  ForgeAuthState get current => ForgeAuthState(
    event: ForgeAuthEvent.initial,
    session: _session(_auth.currentUser),
  );

  @override
  Stream<ForgeAuthState> get changes async* {
    yield current;
    yield* _auth.onAuthStateChange.map(mapState);
  }

  @override
  Future<ForgeAuthResult> signInWithGoogle() async {
    final google = _google;
    if (google == null) {
      return const ForgeAuthFailure(
        ForgeAuthError.misconfigured,
        'Google sign-in is not configured for this build',
      );
    }
    final GoogleIdToken token;
    try {
      token = await google.idToken();
    } on GoogleIdTokenException catch (e) {
      return switch (e.code) {
        GoogleIdTokenFailure.cancelled => const ForgeAuthCancelled(),
        GoogleIdTokenFailure.noAccount => ForgeAuthFailure(
          ForgeAuthError.noGoogleAccount,
          e.message,
        ),
        GoogleIdTokenFailure.unavailable => ForgeAuthFailure(
          ForgeAuthError.googleUnavailable,
          e.message,
        ),
        GoogleIdTokenFailure.misconfigured => ForgeAuthFailure(
          ForgeAuthError.misconfigured,
          e.message,
        ),
        GoogleIdTokenFailure.unknown => ForgeAuthFailure(
          ForgeAuthError.unknown,
          e.message,
        ),
      };
    }
    try {
      final response = await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: token.idToken,
        nonce: token.rawNonce,
      );
      final user = response.user;
      if (user == null) {
        return const ForgeAuthFailure(
          ForgeAuthError.unknown,
          'Supabase returned no user',
        );
      }
      return ForgeAuthSuccess(ForgeSession.fromSupabase(user));
    } on sb.AuthException catch (e) {
      return ForgeAuthFailure(mapAuthException(e), e.message);
    }
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    await _auth.signOut(
      scope: everywhere ? sb.SignOutScope.global : sb.SignOutScope.local,
    );
    await _google?.signOut();
  }

  /// Supabase's state → ours. Pure, so it can be tested without a client.
  static ForgeAuthState mapState(sb.AuthState state) => ForgeAuthState(
    event: mapEvent(state.event),
    session: _session(state.session?.user),
  );

  static ForgeAuthEvent mapEvent(sb.AuthChangeEvent event) => switch (event) {
    sb.AuthChangeEvent.initialSession => ForgeAuthEvent.initial,
    sb.AuthChangeEvent.signedIn => ForgeAuthEvent.signedIn,
    sb.AuthChangeEvent.signedOut => ForgeAuthEvent.signedOut,
    sb.AuthChangeEvent.tokenRefreshed => ForgeAuthEvent.tokenRefreshed,
    sb.AuthChangeEvent.userUpdated => ForgeAuthEvent.userUpdated,
    sb.AuthChangeEvent.passwordRecovery => ForgeAuthEvent.passwordRecovery,
    _ => ForgeAuthEvent.other,
  };

  /// A Supabase auth error → ours. A fetch that may succeed on retry is a
  /// network problem; a `misconfigured` provider comes back as a 4xx the
  /// email flows (FC-5) will refine further.
  static ForgeAuthError mapAuthException(sb.AuthException e) =>
      e is sb.AuthRetryableFetchException
      ? ForgeAuthError.network
      : ForgeAuthError.unknown;

  static ForgeSession? _session(sb.User? user) =>
      user == null ? null : ForgeSession.fromSupabase(user);
}
