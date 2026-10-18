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

  /// What [signInWithGoogle] returns next. Defaults to signing in
  /// [fakeSession]; set a [ForgeAuthCancelled] or [ForgeAuthFailure] to
  /// exercise the other branches.
  ForgeAuthResult googleResult = const ForgeAuthSuccess(fakeSession);

  /// How many times [signInWithGoogle] was called.
  int googleSignIns = 0;

  /// Scripted results for the email flows. Defaults: sign-up and resend
  /// report a confirmation mail, reset reports a reset mail, sign-in and
  /// password update sign [fakeSession] in.
  ForgeAuthResult? signUpResult;
  ForgeAuthResult signInResult = const ForgeAuthSuccess(fakeSession);
  ForgeAuthResult? resendResult;
  ForgeAuthResult? resetResult;
  ForgeAuthResult updatePasswordResult = const ForgeAuthSuccess(fakeSession);

  /// What the app asked for, in order.
  final List<(String, String)> signUps = [];
  final List<(String, String)> signIns = [];
  final List<String> resends = [];
  final List<String> resets = [];
  final List<String> passwordUpdates = [];

  /// The account the fake signs in by default.
  static const fakeSession = ForgeSession(
    userId: 'fake-user',
    email: 'fake@example.com',
    emailConfirmed: true,
    identities: [
      ForgeIdentity(
        id: 'fake-google',
        provider: ForgeIdentityProvider.google,
        email: 'fake@example.com',
      ),
    ],
  );

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
  Future<ForgeAuthResult> signInWithGoogle() async {
    googleSignIns++;
    final result = googleResult;
    if (result is ForgeAuthSuccess) signIn(result.session);
    return result;
  }

  @override
  Future<ForgeAuthResult> signUpWithEmail(String email, String password) async {
    signUps.add((email, password));
    return _settle(
      signUpResult ?? ForgeAuthEmailSent(email, ForgeMailPurpose.confirmation),
    );
  }

  @override
  Future<ForgeAuthResult> signInWithEmail(String email, String password) async {
    signIns.add((email, password));
    return _settle(signInResult);
  }

  @override
  Future<ForgeAuthResult> resendConfirmation(String email) async {
    resends.add(email);
    return resendResult ??
        ForgeAuthEmailSent(email, ForgeMailPurpose.confirmation);
  }

  @override
  Future<ForgeAuthResult> sendPasswordReset(String email) async {
    resets.add(email);
    return resetResult ??
        ForgeAuthEmailSent(email, ForgeMailPurpose.passwordReset);
  }

  @override
  Future<ForgeAuthResult> updatePassword(String newPassword) async {
    passwordUpdates.add(newPassword);
    return _settle(updatePasswordResult);
  }

  /// A success also signs the fake in, as the real stream would.
  ForgeAuthResult _settle(ForgeAuthResult result) {
    if (result is ForgeAuthSuccess) signIn(result.session);
    return result;
  }

  @override
  Future<void> signOut({bool everywhere = false}) async {
    signOutCalls.add(everywhere);
    emit(const ForgeAuthState(event: ForgeAuthEvent.signedOut));
  }

  Future<void> dispose() => _controller.close();
}
