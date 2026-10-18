import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/src/auth/forge_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

void main() {
  group('isValidRedirectUrl', () {
    test('accepts empty and well-formed custom schemes', () {
      expect(SupabaseForgeAuth.isValidRedirectUrl(''), isTrue);
      expect(
        SupabaseForgeAuth.isValidRedirectUrl('com.example.app://auth-callback'),
        isTrue,
      );
      expect(
        SupabaseForgeAuth.isValidRedirectUrl('https://example.com/callback'),
        isTrue,
      );
    });

    test('rejects an application id with an underscore, and junk', () {
      // The real case: Android allows `_` in a package name; URL schemes
      // do not, so GoTrue falls back to the Site URL and Dart's Uri throws.
      expect(
        SupabaseForgeAuth.isValidRedirectUrl(
          'com.tkforgeworks.cheesy_scribe://auth-callback',
        ),
        isFalse,
      );
      expect(SupabaseForgeAuth.isValidRedirectUrl('auth-callback'), isFalse);
      expect(SupabaseForgeAuth.isValidRedirectUrl('myapp://'), isFalse);
    });
  });

  test('SupabaseForgeAuth asserts on an invalid redirect', () {
    final client = sb.GoTrueClient(
      url: 'http://localhost:9999/auth/v1',
      flowType: sb.AuthFlowType.implicit,
    );
    expect(
      () => SupabaseForgeAuth(
        client,
        emailRedirectUrl: 'com.tkforgeworks.cheesy_scribe://auth-callback',
      ),
      throwsA(isA<AssertionError>()),
    );
    expect(
      SupabaseForgeAuth(
        client,
        emailRedirectUrl: 'com.tkforgeworks.cheesyscribe://auth-callback',
      ),
      isA<ForgeAuth>(),
    );
  });
}
