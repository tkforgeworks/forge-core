/// Test doubles for apps built on forge_core. Import in tests only.
library;

import 'dart:async';

import 'package:forge_core/forge_core.dart';

/// A [ForgeEntriesRepository] over an in-memory table, for app sync tests.
/// Seed or inspect [rows]; use [remoteUpsert] to play another device.
class FakeForgeEntriesRepository<T> implements ForgeEntriesRepository<T> {
  FakeForgeEntriesRepository(this.auth, {this.pageSize = 500});

  final FakeForgeAuth auth;
  final int pageSize;

  /// The server's rows by id.
  final Map<String, ForgeEntry<T>> rows = {};

  /// Set to make the next call fail.
  ForgeDataError? nextError;

  /// Every call made, as `(name, argument)`, in order.
  final List<(String, Object?)> calls = [];

  ForgeResult<R>? _check<R>(String name, Object? arg) {
    calls.add((name, arg));
    final error = nextError;
    if (error != null) {
      nextError = null;
      return ForgeFailed<R>(error, error.name);
    }
    if (auth.current.session == null) {
      return const ForgeFailed(ForgeDataError.sessionMissing, 'Not signed in');
    }
    return null;
  }

  /// Another device wrote these rows.
  void remoteUpsert(Iterable<ForgeEntry<T>> entries) {
    for (final e in entries) {
      rows[e.id] = e;
    }
  }

  @override
  Future<ForgeResult<void>> upsertAll(Iterable<ForgeEntry<T>> entries) async {
    final list = entries.toList();
    final failed = _check<void>('upsertAll', list);
    if (failed != null) return failed;
    for (final e in list) {
      rows[e.id] = ForgeEntry<T>(
        id: e.id,
        data: e.isDeleted ? null : e.data,
        updatedAt: e.updatedAt,
        createdAt: rows[e.id]?.createdAt ?? e.createdAt ?? e.updatedAt,
        deletedAt: e.deletedAt,
      );
    }
    return const ForgeOk(null);
  }

  @override
  Future<ForgeResult<List<ForgeEntryKey>>> listKeys({DateTime? since}) async {
    final failed = _check<List<ForgeEntryKey>>('listKeys', since);
    if (failed != null) return failed;
    final keys =
        [
          for (final e in rows.values)
            if (since == null || e.updatedAt.isAfter(since))
              ForgeEntryKey(
                id: e.id,
                updatedAt: e.updatedAt,
                deletedAt: e.deletedAt,
              ),
        ]..sort((a, b) {
          final byTime = a.updatedAt.compareTo(b.updatedAt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
    return ForgeOk(keys);
  }

  @override
  Future<ForgeResult<List<ForgeEntry<T>>>> fetchByIds(
    Iterable<String> ids,
  ) async {
    final list = ids.toList();
    final failed = _check<List<ForgeEntry<T>>>('fetchByIds', list);
    if (failed != null) return failed;
    return ForgeOk([for (final id in list) ?rows[id]]);
  }

  @override
  Future<ForgeResult<void>> markDeleted(
    Iterable<String> ids,
    DateTime at,
  ) async {
    final list = ids.toList();
    final failed = _check<void>('markDeleted', list);
    if (failed != null) return failed;
    for (final id in list) {
      rows[id] = ForgeEntry<T>(
        id: id,
        data: null,
        updatedAt: at,
        createdAt: rows[id]?.createdAt ?? at,
        deletedAt: at,
      );
    }
    return const ForgeOk(null);
  }
}

/// A [ForgeAccounts] over an in-memory row that follows a [FakeForgeAuth].
class FakeForgeAccounts implements ForgeAccounts {
  FakeForgeAccounts(this.auth, {this.username});

  final FakeForgeAuth auth;

  /// The stored username; set it directly to seed a test.
  String? username;

  /// The account's creation time, for "member since".
  DateTime createdAt = DateTime.utc(2026, 1, 1);

  /// Set to make the next call fail.
  ForgeDataError? nextError;

  /// Every value [setUsername] received, in order.
  final List<String?> usernameWrites = [];

  ForgeAccount? get _row {
    final session = auth.current.session;
    return session == null
        ? null
        : ForgeAccount(
            userId: session.userId,
            username: username,
            createdAt: createdAt,
          );
  }

  ForgeResult<T>? _failure<T>() {
    final error = nextError;
    if (error == null) return null;
    nextError = null;
    return ForgeFailed<T>(error, error.name);
  }

  @override
  Future<ForgeResult<ForgeAccount?>> getAccount() async =>
      _failure<ForgeAccount?>() ?? ForgeOk(_row);

  @override
  Stream<ForgeResult<ForgeAccount?>> watchAccount() =>
      auth.changes.asyncMap((_) => getAccount());

  @override
  Future<ForgeResult<ForgeAccount>> setUsername(String? value) async {
    usernameWrites.add(value);
    final failed = _failure<ForgeAccount>();
    if (failed != null) return failed;
    final row = _row;
    if (row == null) {
      return const ForgeFailed(ForgeDataError.sessionMissing, 'Not signed in');
    }
    final trimmed = value?.trim() ?? '';
    if (trimmed.length > ForgeAccounts.maxUsernameLength) {
      return const ForgeFailed(ForgeDataError.invalid, 'too long');
    }
    username = trimmed.isEmpty ? null : trimmed;
    return ForgeOk(_row!);
  }
}

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

  /// Scripted results for linking. Defaults: linking Google adds a Google
  /// identity to the current session; unlinking removes the given one.
  ForgeAuthResult? linkGoogleResult;
  ForgeAuthResult? unlinkResult;
  int linkGoogleCalls = 0;
  final List<ForgeIdentity> unlinks = [];

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
        identityId: 'fake-google-link',
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

  @override
  Future<ForgeAuthResult> linkGoogle() async {
    linkGoogleCalls++;
    final scripted = linkGoogleResult;
    if (scripted != null) return _update(scripted);
    final session = _current.session;
    if (session == null) {
      return const ForgeAuthFailure(
        ForgeAuthError.sessionMissing,
        'no session',
      );
    }
    final linked = ForgeSession(
      userId: session.userId,
      email: session.email,
      emailConfirmed: session.emailConfirmed,
      createdAt: session.createdAt,
      identities: [
        ...session.identities,
        ForgeIdentity(
          id: 'fake-google',
          identityId: 'fake-google-link',
          provider: ForgeIdentityProvider.google,
          email: session.email,
        ),
      ],
    );
    return _update(ForgeAuthSuccess(linked));
  }

  @override
  Future<ForgeAuthResult> unlinkIdentity(ForgeIdentity identity) async {
    unlinks.add(identity);
    final scripted = unlinkResult;
    if (scripted != null) return _update(scripted);
    final session = _current.session;
    if (session == null) {
      return const ForgeAuthFailure(
        ForgeAuthError.sessionMissing,
        'no session',
      );
    }
    if (session.identities.length <= 1) {
      return const ForgeAuthFailure(
        ForgeAuthError.lastSignInMethod,
        'only sign-in method',
      );
    }
    final remaining = ForgeSession(
      userId: session.userId,
      email: session.email,
      emailConfirmed: session.emailConfirmed,
      createdAt: session.createdAt,
      identities: [
        for (final i in session.identities)
          if (i.identityId != identity.identityId) i,
      ],
    );
    return _update(ForgeAuthSuccess(remaining));
  }

  @override
  Future<ForgeAuthResult> setPassword(String password) =>
      updatePassword(password);

  /// A success replaces the session without a sign-in event (userUpdated).
  ForgeAuthResult _update(ForgeAuthResult result) {
    if (result is ForgeAuthSuccess) {
      emit(
        ForgeAuthState(
          event: ForgeAuthEvent.userUpdated,
          session: result.session,
        ),
      );
    }
    return result;
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
