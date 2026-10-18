import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/testing.dart';

void main() {
  const tim = ForgeSession(userId: 'u1', email: 'tim@example.com');

  test('changes replays the current state, then every emit', () async {
    final auth = FakeForgeAuth();
    addTearDown(auth.dispose);
    final seen = <ForgeAuthState>[];
    final sub = auth.changes.listen(seen.add);
    await pumpEventQueue();
    auth.signIn(tim);
    auth.startPasswordRecovery(tim);
    await auth.signOut(everywhere: true);
    await pumpEventQueue();
    await sub.cancel();

    expect(seen.map((s) => s.event), [
      ForgeAuthEvent.initial,
      ForgeAuthEvent.signedIn,
      ForgeAuthEvent.passwordRecovery,
      ForgeAuthEvent.signedOut,
    ]);
    expect(seen[1].session, tim);
    expect(seen[2].isPasswordRecovery, isTrue);
    expect(auth.current.isSignedIn, isFalse);
    expect(auth.signOutCalls, [true]);
  });

  test('signInWithGoogle follows the scripted result', () async {
    final auth = FakeForgeAuth();
    addTearDown(auth.dispose);
    expect(await auth.signInWithGoogle(), isA<ForgeAuthSuccess>());
    expect(auth.current.session, FakeForgeAuth.fakeSession);
    expect(auth.googleSignIns, 1);
    auth.googleResult = const ForgeAuthCancelled();
    expect(await auth.signInWithGoogle(), const ForgeAuthCancelled());
    expect(auth.googleSignIns, 2);
    expect(auth.current.session, FakeForgeAuth.fakeSession); // unchanged
  });

  test('email flows record calls and follow their scripted results', () async {
    final auth = FakeForgeAuth();
    addTearDown(auth.dispose);
    expect(
      await auth.signUpWithEmail('a@b.co', 'hunter22'),
      const ForgeAuthEmailSent('a@b.co', ForgeMailPurpose.confirmation),
    );
    expect(auth.current.isSignedIn, isFalse);
    expect(
      await auth.sendPasswordReset('a@b.co'),
      const ForgeAuthEmailSent('a@b.co', ForgeMailPurpose.passwordReset),
    );
    expect(await auth.resendConfirmation('a@b.co'), isA<ForgeAuthEmailSent>());
    auth.signInResult = const ForgeAuthFailure(
      ForgeAuthError.invalidCredentials,
      'nope',
    );
    expect(
      await auth.signInWithEmail('a@b.co', 'wrong'),
      isA<ForgeAuthFailure>(),
    );
    auth.signInResult = const ForgeAuthSuccess(FakeForgeAuth.fakeSession);
    expect(
      await auth.signInWithEmail('a@b.co', 'right'),
      isA<ForgeAuthSuccess>(),
    );
    expect(auth.current.isSignedIn, isTrue);
    expect(await auth.updatePassword('newpassword1'), isA<ForgeAuthSuccess>());
    expect(auth.signUps, [('a@b.co', 'hunter22')]);
    expect(auth.signIns, [('a@b.co', 'wrong'), ('a@b.co', 'right')]);
    expect(auth.resets, ['a@b.co']);
    expect(auth.resends, ['a@b.co']);
    expect(auth.passwordUpdates, ['newpassword1']);
  });

  test('a late listener gets the signed-in state first', () async {
    final auth = FakeForgeAuth(
      initial: const ForgeAuthState(
        event: ForgeAuthEvent.initial,
        session: tim,
      ),
    );
    addTearDown(auth.dispose);
    expect((await auth.changes.first).session, tim);
    expect(auth.current.isSignedIn, isTrue);
  });
}
