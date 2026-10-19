import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

sb.User _user({
  String? email = 'tim@example.com',
  String? emailConfirmedAt = '2026-10-18T12:00:00Z',
  List<Map<String, dynamic>> identities = const [],
}) => sb.User.fromJson({
  'id': 'user-1',
  'aud': 'authenticated',
  'app_metadata': <String, dynamic>{},
  'user_metadata': <String, dynamic>{},
  'created_at': '2026-10-01T08:30:00Z',
  'email': ?email,
  'email_confirmed_at': ?emailConfirmedAt,
  'identities': identities,
})!;

Map<String, dynamic> _identity(String provider, {String? email}) => {
  'id': 'id-$provider',
  'user_id': 'user-1',
  'identity_id': 'iid-$provider',
  'provider': provider,
  'identity_data': {'email': ?email},
};

void main() {
  group('ForgeSession.fromSupabase', () {
    test('maps the user, confirmation and identities to plain types', () {
      final session = ForgeSession.fromSupabase(
        _user(
          identities: [
            _identity('google', email: 'tim@gmail.example'),
            _identity('email', email: 'tim@example.com'),
            _identity('phone'),
          ],
        ),
      );
      expect(session.userId, 'user-1');
      expect(session.email, 'tim@example.com');
      expect(session.emailConfirmed, isTrue);
      expect(session.createdAt, DateTime.utc(2026, 10, 1, 8, 30));
      expect(session.identities, [
        const ForgeIdentity(
          id: 'id-google',

          identityId: 'iid-google',
          provider: ForgeIdentityProvider.google,
          email: 'tim@gmail.example',
        ),
        const ForgeIdentity(
          id: 'id-email',

          identityId: 'iid-email',
          provider: ForgeIdentityProvider.email,
          email: 'tim@example.com',
        ),
        const ForgeIdentity(
          id: 'id-phone',

          identityId: 'iid-phone',
          provider: ForgeIdentityProvider.other,
        ),
      ]);
      expect(session.has(ForgeIdentityProvider.google), isTrue);
      expect(session.has(ForgeIdentityProvider.apple), isFalse);
    });

    test('an unconfirmed email sign-up is not confirmed', () {
      final session = ForgeSession.fromSupabase(_user(emailConfirmedAt: null));
      expect(session.emailConfirmed, isFalse);
      expect(session.identities, isEmpty);
    });

    test('provider names map case-insensitively, unknown → other', () {
      expect(
        ForgeIdentityProvider.fromName('Google'),
        ForgeIdentityProvider.google,
      );
      expect(
        ForgeIdentityProvider.fromName('apple'),
        ForgeIdentityProvider.apple,
      );
      expect(
        ForgeIdentityProvider.fromName('email'),
        ForgeIdentityProvider.email,
      );
      expect(
        ForgeIdentityProvider.fromName('github'),
        ForgeIdentityProvider.other,
      );
    });
  });

  group('SupabaseForgeAuth.mapState', () {
    test('maps every Supabase event and carries the session', () {
      final user = _user();
      final session = sb.Session(
        accessToken: 'a',
        tokenType: 'bearer',
        user: user,
      );
      const cases = {
        sb.AuthChangeEvent.initialSession: ForgeAuthEvent.initial,
        sb.AuthChangeEvent.signedIn: ForgeAuthEvent.signedIn,
        sb.AuthChangeEvent.signedOut: ForgeAuthEvent.signedOut,
        sb.AuthChangeEvent.tokenRefreshed: ForgeAuthEvent.tokenRefreshed,
        sb.AuthChangeEvent.userUpdated: ForgeAuthEvent.userUpdated,
        sb.AuthChangeEvent.passwordRecovery: ForgeAuthEvent.passwordRecovery,
        sb.AuthChangeEvent.mfaChallengeVerified: ForgeAuthEvent.other,
      };
      for (final entry in cases.entries) {
        final mapped = SupabaseForgeAuth.mapState(
          sb.AuthState(entry.key, session),
        );
        expect(mapped.event, entry.value, reason: entry.key.name);
        expect(mapped.session, ForgeSession.fromSupabase(user));
        expect(mapped.isSignedIn, isTrue);
      }
      final out = SupabaseForgeAuth.mapState(
        const sb.AuthState(sb.AuthChangeEvent.signedOut, null),
      );
      expect(out.isSignedIn, isFalse);
      expect(out.isPasswordRecovery, isFalse);
      expect(
        SupabaseForgeAuth.mapState(
          sb.AuthState(sb.AuthChangeEvent.passwordRecovery, session),
        ).isPasswordRecovery,
        isTrue,
      );
    });
  });

  group('ForgeCore.withClient', () {
    test(
      'wraps a client; nobody is signed in until someone signs in',
      () async {
        const config = ForgeSupabaseConfig(
          url: 'https://abc.supabase.co',
          publishableKey: 'sb_publishable_x',
        );
        final core = ForgeCore.withClient(
          sb.SupabaseClient(config.url, config.publishableKey),
          config,
        );
        addTearDown(core.dispose);
        expect(core.config, config);
        expect(core.auth, isA<SupabaseForgeAuth>());
        expect(core.auth.current, ForgeAuthState.signedOut);
        expect(await core.auth.changes.first, ForgeAuthState.signedOut);
      },
    );
  });
}
