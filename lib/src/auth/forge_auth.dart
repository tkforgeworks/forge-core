import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'forge_session.dart';

/// Session state and sign-out, in plain types. Apps wrap [changes] in their
/// state layer (a Riverpod `StreamProvider`, say) and never touch Supabase.
///
/// Sign-in methods arrive in later tickets (Google: FC-4, email: FC-5) on
/// this same object. The production implementation is [SupabaseForgeAuth];
/// `package:forge_core/testing.dart` has a fake for app tests.
abstract class ForgeAuth {
  /// The state right now.
  ForgeAuthState get current;

  /// Emits [current] first, then every change. A broadcast stream: listen
  /// from as many places as you like.
  Stream<ForgeAuthState> get changes;

  /// Ends the session on this device, or on every device with [everywhere]
  /// (account deletion uses that). Never touches the app's own storage.
  Future<void> signOut({bool everywhere = false});
}

/// [ForgeAuth] over a Supabase client.
class SupabaseForgeAuth implements ForgeAuth {
  SupabaseForgeAuth(this._auth);

  final sb.GoTrueClient _auth;

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
  Future<void> signOut({bool everywhere = false}) => _auth.signOut(
    scope: everywhere ? sb.SignOutScope.global : sb.SignOutScope.local,
  );

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

  static ForgeSession? _session(sb.User? user) =>
      user == null ? null : ForgeSession.fromSupabase(user);
}
