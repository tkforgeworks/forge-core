/// Test doubles for apps built on forge_core. Import in tests only.
library;

import 'dart:async';

import 'package:forge_core/forge_core.dart';

/// A [ForgeAuth] a test drives by hand: set the session, emit events, and
/// check what the app asked for.
class FakeForgeAuth implements ForgeAuth {
  FakeForgeAuth({ForgeAuthState initial = ForgeAuthState.signedOut})
    : _current = initial;

  ForgeAuthState _current;
  final _controller = StreamController<ForgeAuthState>.broadcast();

  /// Every [signOut] call's `everywhere` argument, in order.
  final List<bool> signOutCalls = [];

  @override
  ForgeAuthState get current => _current;

  @override
  Stream<ForgeAuthState> get changes async* {
    yield _current;
    yield* _controller.stream;
  }

  /// Moves to [state] and notifies listeners.
  void emit(ForgeAuthState state) {
    _current = state;
    _controller.add(state);
  }

  /// Shorthand: a user signed in.
  void signIn(ForgeSession session) =>
      emit(ForgeAuthState(event: ForgeAuthEvent.signedIn, session: session));

  /// Shorthand: the app was opened from a password-reset link.
  void startPasswordRecovery(ForgeSession session) => emit(
    ForgeAuthState(event: ForgeAuthEvent.passwordRecovery, session: session),
  );

  @override
  Future<void> signOut({bool everywhere = false}) async {
    signOutCalls.add(everywhere);
    emit(const ForgeAuthState(event: ForgeAuthEvent.signedOut));
  }

  Future<void> dispose() => _controller.close();
}
