import 'package:flutter/foundation.dart';

/// Where an app's Supabase project is and how the app talks to it.
///
/// The values are public by design (the publishable key is meant to ship in
/// the app) but are never committed: they arrive as `--dart-define`s read by
/// [ForgeSupabaseConfig.fromEnvironment]. Locally that is a gitignored
/// `--dart-define-from-file` JSON; in release builds the org pipeline passes
/// them from repository secrets. A build without them is still a valid build
/// ([isConfigured] is false) so an app can show "backup isn't available in
/// this build" instead of failing.
@immutable
class ForgeSupabaseConfig {
  const ForgeSupabaseConfig({
    required this.url,
    required this.publishableKey,
    this.googleWebClientId = '',
    this.authRedirectUrl = '',
  });

  /// Reads [urlDefine], [publishableKeyDefine] and [googleWebClientIdDefine]
  /// from the build's `--dart-define`s; each is empty when absent.
  /// [authRedirectUrl] is app code, not configuration: pass the app's own
  /// custom scheme.
  const ForgeSupabaseConfig.fromEnvironment({this.authRedirectUrl = ''})
    : url = const String.fromEnvironment(urlDefine),
      publishableKey = const String.fromEnvironment(publishableKeyDefine),
      googleWebClientId = const String.fromEnvironment(googleWebClientIdDefine);

  /// `--dart-define` names.
  static const urlDefine = 'FORGE_SUPABASE_URL';
  static const publishableKeyDefine = 'FORGE_SUPABASE_PUBLISHABLE_KEY';
  static const googleWebClientIdDefine = 'FORGE_GOOGLE_WEB_CLIENT_ID';

  /// The project URL, `https://<ref>.supabase.co`.
  final String url;

  /// The project's `sb_publishable_…` key (the legacy `anon` key also works
  /// until Supabase retires it).
  final String publishableKey;

  /// The Google Cloud **Web** OAuth client ID: the Supabase Google provider's
  /// client ID and the `serverClientId` native sign-in asks a token for.
  /// Empty when the app offers no Google sign-in.
  final String googleWebClientId;

  /// Where confirmation and password-reset emails send the user back to:
  /// the app's custom scheme, `<applicationId>://auth-callback`, which must
  /// also be on the Supabase project's redirect allow list and declared as
  /// an `intent-filter` in the Android manifest. Empty means the project's
  /// Site URL (a web page), which no app wants.
  final String authRedirectUrl;

  /// True when the app can reach a Supabase project at all.
  bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// True when Google sign-in can be offered.
  bool get hasGoogle => isConfigured && googleWebClientId.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeSupabaseConfig &&
          other.url == url &&
          other.publishableKey == publishableKey &&
          other.googleWebClientId == googleWebClientId &&
          other.authRedirectUrl == authRedirectUrl;

  @override
  int get hashCode =>
      Object.hash(url, publishableKey, googleWebClientId, authRedirectUrl);

  /// Never prints the key.
  @override
  String toString() =>
      'ForgeSupabaseConfig(${isConfigured ? url : 'unconfigured'}'
      '${hasGoogle ? ', google' : ''})';
}
