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
