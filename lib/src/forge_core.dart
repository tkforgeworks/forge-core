import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth/forge_auth.dart';
import 'auth/google_id_token_source.dart';
import 'config/forge_supabase_config.dart';

/// The app's handle on its Supabase project: one initialised client and the
/// plain-typed services over it. Create it once in `main()` with
/// [ForgeCore.initialize] and hand it to your state layer.
///
/// ```dart
/// const config = ForgeSupabaseConfig.fromEnvironment();
/// final core = config.isConfigured ? await ForgeCore.initialize(config) : null;
/// ```
///
/// A null [ForgeCore] is how an app runs with no backend configured (a
/// build without `--dart-define`s): it keeps working locally and tells the
/// user backup isn't available in this build.
class ForgeCore {
  /// Wraps an already-created client. [initialize] is the usual path; this
  /// one is for tests and for apps that set Supabase up themselves. Pass
  /// [google] to offer Google sign-in (tests pass a fake source).
  ForgeCore.withClient(this.client, this.config, {GoogleIdTokenSource? google})
    : auth = SupabaseForgeAuth(
        client.auth,
        google: google,
        emailRedirectUrl: config.authRedirectUrl,
      );

  /// Initialises Supabase for [config] (PKCE auth flow, session persisted on
  /// the device, deep links handled) and returns the handle. Google sign-in
  /// is offered when the config has a web client ID.
  static Future<ForgeCore> initialize(
    ForgeSupabaseConfig config, {
    bool debug = false,
  }) async {
    assert(config.isConfigured, 'ForgeCore.initialize needs a URL and a key');
    final supabase = await sb.Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      debug: debug,
    );
    return ForgeCore.withClient(
      supabase.client,
      config,
      google: config.hasGoogle
          ? PluginGoogleIdTokenSource(serverClientId: config.googleWebClientId)
          : null,
    );
  }

  final ForgeSupabaseConfig config;

  /// The raw client, for the few places a package call doesn't cover yet.
  /// Prefer the typed services; nothing in an app should need this long term.
  final sb.SupabaseClient client;

  /// Session state and sign-out.
  final ForgeAuth auth;

  /// Releases the client's resources (tests; apps live as long as the
  /// process).
  Future<void> dispose() => client.dispose();
}
