import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';

void main() {
  group('ForgeSupabaseConfig', () {
    test('a build with no dart-defines is unconfigured, not broken', () {
      const config = ForgeSupabaseConfig.fromEnvironment();
      expect(config.url, isEmpty);
      expect(config.isConfigured, isFalse);
      expect(config.hasGoogle, isFalse);
      expect(config.toString(), 'ForgeSupabaseConfig(unconfigured)');
    });

    test('needs a URL and a key; Google needs the web client ID too', () {
      const base = ForgeSupabaseConfig(
        url: 'https://abc.supabase.co',
        publishableKey: 'sb_publishable_x',
      );
      expect(base.isConfigured, isTrue);
      expect(base.hasGoogle, isFalse);
      expect(
        const ForgeSupabaseConfig(
          url: 'https://abc.supabase.co',
          publishableKey: '',
        ).isConfigured,
        isFalse,
      );
      const withGoogle = ForgeSupabaseConfig(
        url: 'https://abc.supabase.co',
        publishableKey: 'sb_publishable_x',
        googleWebClientId: '123.apps.googleusercontent.com',
      );
      expect(withGoogle.hasGoogle, isTrue);
      expect(withGoogle, isNot(equals(base)));
      expect(
        withGoogle,
        const ForgeSupabaseConfig(
          url: 'https://abc.supabase.co',
          publishableKey: 'sb_publishable_x',
          googleWebClientId: '123.apps.googleusercontent.com',
        ),
      );
    });

    test('toString never includes the key', () {
      const config = ForgeSupabaseConfig(
        url: 'https://abc.supabase.co',
        publishableKey: 'sb_publishable_secret-looking',
        googleWebClientId: 'g',
      );
      expect(config.toString(), isNot(contains('sb_publishable')));
      expect(
        config.toString(),
        'ForgeSupabaseConfig(https://abc.supabase.co, google)',
      );
    });

    test('the redirect URL is app code, carried alongside the defines', () {
      const config = ForgeSupabaseConfig.fromEnvironment(
        authRedirectUrl: 'com.example.app://auth-callback',
      );
      expect(config.authRedirectUrl, 'com.example.app://auth-callback');
      expect(config.isConfigured, isFalse);
      expect(
        const ForgeSupabaseConfig(url: 'u', publishableKey: 'k'),
        isNot(
          equals(
            const ForgeSupabaseConfig(
              url: 'u',
              publishableKey: 'k',
              authRedirectUrl: 'x://y',
            ),
          ),
        ),
      );
    });

    test('the dart-define names are the documented ones', () {
      expect(ForgeSupabaseConfig.urlDefine, 'FORGE_SUPABASE_URL');
      expect(
        ForgeSupabaseConfig.publishableKeyDefine,
        'FORGE_SUPABASE_PUBLISHABLE_KEY',
      );
      expect(
        ForgeSupabaseConfig.googleWebClientIdDefine,
        'FORGE_GOOGLE_WEB_CLIENT_ID',
      );
    });
  });
}
