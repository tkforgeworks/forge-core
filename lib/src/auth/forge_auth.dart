import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'forge_auth_result.dart';
import 'forge_session.dart';
import 'google_id_token_source.dart';

/// Session state, sign-in, linking and sign-out, in plain types. Apps wrap
/// [changes] in their state layer (a Riverpod `StreamProvider`, say) and
/// never touch Supabase.
///
/// Every call returns a [ForgeAuthResult] and never throws. The production
/// implementation is [SupabaseForgeAuth]; `package:forge_core/testing.dart`
/// has a fake for app tests.
abstract class ForgeAuth {
  /// The state right now.
  ForgeAuthState get current;

  /// Emits [current] first, then every change. A broadcast stream: listen
  /// from as many places as you like.
  Stream<ForgeAuthState> get changes;

  /// Native Google sign-in: the account picker, then the ID token exchanged
  /// with Supabase. Never throws; every outcome is a [ForgeAuthResult].
  Future<ForgeAuthResult> signInWithGoogle();

  /// Creates an email/password account. With confirmation required (every
  /// tkforgeworks project) the result is [ForgeAuthEmailSent] and the
  /// session arrives through [changes] once the link is opened on this
  /// device; an existing address is [ForgeAuthError.emailTaken].
  Future<ForgeAuthResult> signUpWithEmail(String email, String password);

  /// Email/password sign-in. An unconfirmed account is
  /// [ForgeAuthError.emailNotConfirmed]: offer [resendConfirmation].
  Future<ForgeAuthResult> signInWithEmail(String email, String password);

  /// Sends the confirmation mail again.
  Future<ForgeAuthResult> resendConfirmation(String email);

  /// Sends a password-reset link. Opening it on this device signs the user
  /// in with a [ForgeAuthEvent.passwordRecovery] state; the app then shows
  /// its set-password screen and calls [updatePassword].
  Future<ForgeAuthResult> sendPasswordReset(String email);

  /// Sets a new password for the signed-in user (after a reset link, or to
  /// add a password to a Google-only account; [setPassword] is the same
  /// call under the name the account page uses).
  Future<ForgeAuthResult> updatePassword(String newPassword);

  /// Adds email/password sign-in to a Google-only account. The account's
  /// email is already known, so this is [updatePassword].
  Future<ForgeAuthResult> setPassword(String password);

  /// Attaches the Google account the user picks to the signed-in account,
  /// natively. [ForgeAuthError.identityAlreadyLinked] when that Google
  /// account belongs to someone else; needs "Allow manual linking" on the
  /// Supabase project. On success [changes] emits `userUpdated` with the
  /// new identity list.
  Future<ForgeAuthResult> linkGoogle();

  /// Removes one sign-in method. Refused as [ForgeAuthError.lastSignInMethod]
  /// when it is the only one, before any request.
  Future<ForgeAuthResult> unlinkIdentity(ForgeIdentity identity);

  /// Ends the session on this device, or on every device with [everywhere]
  /// (account deletion uses that). Never touches the app's own storage.
  Future<void> signOut({bool everywhere = false});

  /// Completes a confirmation or reset mail link that opened the app
  /// (FC-13): the templates link to the app's redirect URL with
  /// `token_hash` and `type`, and this verifies the token with the server.
  /// Null when [link] carries no token (a link this package did not make);
  /// otherwise the result, which on success also reaches [changes] as
  /// `signedIn` or `passwordRecovery`, and on failure as
  /// [ForgeAuthEvent.mailLinkFailed]. The production implementation calls
  /// this itself for every incoming link, so apps only need it in tests or
  /// when they route links by hand.
  Future<ForgeAuthResult?> handleLink(Uri link);
}

/// The token a mail link carries, when it is one of ours (FC-13):
/// `?token_hash=…&type=signup|recovery|email_change|magiclink|…`, appended
/// to the app's redirect URL by `supabase/templates/*.html`.
@immutable
class ForgeMailLink {
  const ForgeMailLink({required this.tokenHash, required this.type});

  /// Null when [uri] has no token hash and type.
  static ForgeMailLink? parse(Uri uri) {
    final tokenHash = uri.queryParameters['token_hash'];
    final type = uri.queryParameters['type'];
    if (tokenHash == null ||
        tokenHash.isEmpty ||
        type == null ||
        type.isEmpty) {
      return null;
    }
    return ForgeMailLink(tokenHash: tokenHash, type: type);
  }

  final String tokenHash;

  /// Supabase's verification type, as the template wrote it.
  final String type;

  /// A password-reset link: verifying it yields `passwordRecovery`.
  bool get isPasswordReset => type == 'recovery';

  @override
  bool operator ==(Object other) =>
      other is ForgeMailLink &&
      other.tokenHash == tokenHash &&
      other.type == type;

  @override
  int get hashCode => Object.hash(tokenHash, type);

  @override
  String toString() => 'ForgeMailLink($type)';
}

/// [ForgeAuth] over a Supabase client. [google] is null when the build has
/// no web client ID, in which case [signInWithGoogle] and [linkGoogle]
/// report [ForgeAuthError.misconfigured]. [emailRedirectUrl] is where
/// confirmation and reset mails send the user back to (the app's custom
/// scheme).
class SupabaseForgeAuth implements ForgeAuth {
  /// [links] is the stream of URIs that open the app (app_links'
  /// `uriLinkStream`, which on mobile includes the one the app was launched
  /// with); every mail link on it is completed with [handleLink].
  SupabaseForgeAuth(
    this._auth, {
    this._google,
    String emailRedirectUrl = '',
    Stream<Uri>? links,
  }) : assert(
         isValidRedirectUrl(emailRedirectUrl),
         'emailRedirectUrl "$emailRedirectUrl" is not a valid URL. A scheme '
         'may only contain letters, digits, "+", "-" and ".", so an '
         'application id with an underscore cannot be used as is: drop '
         'the underscore (com.example.myapp://auth-callback).',
       ),
       _redirect = emailRedirectUrl.isEmpty ? null : emailRedirectUrl {
    _links = links?.listen((uri) => unawaited(handleLink(uri)));
  }

  /// Whether [url] can serve as the mails' redirect: empty (the project's
  /// Site URL), or a URL both Dart and GoTrue can parse. GoTrue silently
  /// falls back to the Site URL for a redirect it cannot parse, even when
  /// the allow list names it, and an Android application id with an
  /// underscore (`com.example.my_app`) is exactly that: `_` is not a scheme
  /// character.
  static bool isValidRedirectUrl(String url) {
    if (url.isEmpty) return true;
    final parsed = Uri.tryParse(url);
    return parsed != null && parsed.hasScheme && parsed.host.isNotEmpty;
  }

  final sb.GoTrueClient _auth;
  final GoogleIdTokenSource? _google;
  final String? _redirect;
  StreamSubscription<Uri>? _links;

  /// States this class adds to Supabase's own: mail links that failed.
  final _extra = StreamController<ForgeAuthState>.broadcast();

  @override
  ForgeAuthState get current => ForgeAuthState(
    event: ForgeAuthEvent.initial,
    session: _session(_auth.currentUser),
  );

  @override
  Stream<ForgeAuthState> get changes async* {
    yield current;
    yield* _merge(_auth.onAuthStateChange.map(mapState), _extra.stream);
  }

  /// Stops watching links. Apps live as long as the process; tests call it.
  Future<void> dispose() async {
    await _links?.cancel();
    await _extra.close();
  }

  @override
  Future<ForgeAuthResult?> handleLink(Uri link) async {
    final mail = ForgeMailLink.parse(link);
    if (mail == null) return null;
    final type = _otpType(mail.type);
    final result = type == null
        ? ForgeAuthFailure(
            ForgeAuthError.unknown,
            'unknown mail link type "${mail.type}"',
          )
        : await _guard(() async {
            final response = await _auth.verifyOTP(
              tokenHash: mail.tokenHash,
              type: type,
            );
            return _success(response.user);
          });
    if (result is ForgeAuthFailure && !_extra.isClosed) {
      _extra.add(
        ForgeAuthState(
          event: ForgeAuthEvent.mailLinkFailed,
          session: current.session,
          error: result.error,
        ),
      );
    }
    return result;
  }

  /// The `type` a template wrote → Supabase's. Null for anything else.
  static sb.OtpType? _otpType(String type) => switch (type) {
    'signup' => sb.OtpType.signup,
    'invite' => sb.OtpType.invite,
    'magiclink' => sb.OtpType.magiclink,
    'recovery' => sb.OtpType.recovery,
    'email_change' => sb.OtpType.emailChange,
    'email' => sb.OtpType.email,
    _ => null,
  };

  static Stream<T> _merge<T>(Stream<T> a, Stream<T> b) {
    late final StreamController<T> out;
    StreamSubscription<T>? subA;
    StreamSubscription<T>? subB;
    out = StreamController<T>(
      onListen: () {
        subA = a.listen(out.add, onError: out.addError);
        subB = b.listen(out.add, onError: out.addError);
      },
      onCancel: () => Future.wait([?subA?.cancel(), ?subB?.cancel()]),
    );
    return out.stream;
  }

  @override
  Future<ForgeAuthResult> signInWithGoogle() async {
    final token = await _googleToken();
    if (token is ForgeAuthResult) return token;
    token as GoogleIdToken;
    return _guard(() async {
      final response = await _auth.signInWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: token.idToken,
        nonce: token.rawNonce,
      );
      return _success(response.user);
    });
  }

  @override
  Future<ForgeAuthResult> linkGoogle() async {
    if (_auth.currentSession == null) {
      return const ForgeAuthFailure(
        ForgeAuthError.sessionMissing,
        'Sign in before linking another method',
      );
    }
    final token = await _googleToken();
    if (token is ForgeAuthResult) return token;
    token as GoogleIdToken;
    return _guard(() async {
      final response = await _auth.linkIdentityWithIdToken(
        provider: sb.OAuthProvider.google,
        idToken: token.idToken,
        nonce: token.rawNonce,
      );
      return _success(response.user);
    });
  }

  @override
  Future<ForgeAuthResult> unlinkIdentity(ForgeIdentity identity) =>
      _guard(() async {
        if (_auth.currentSession == null) {
          return const ForgeAuthFailure(
            ForgeAuthError.sessionMissing,
            'Sign in before unlinking a method',
          );
        }
        final identities =
            _auth.currentUser?.identities ?? await _auth.getUserIdentities();
        if (identities.length <= 1) {
          return const ForgeAuthFailure(
            ForgeAuthError.lastSignInMethod,
            'That is the only way to sign in to this account',
          );
        }
        final target = identities.where(
          (i) => i.identityId == identity.identityId,
        );
        if (target.isEmpty) {
          return const ForgeAuthFailure(
            ForgeAuthError.unknown,
            'That sign-in method is not on this account',
          );
        }
        await _auth.unlinkIdentity(target.first);
        final refreshed = await _auth.getUser();
        return _success(refreshed.user);
      });

  /// The Google ID token, or the [ForgeAuthResult] to return instead.
  Future<Object> _googleToken() async {
    final google = _google;
    if (google == null) {
      return const ForgeAuthFailure(
        ForgeAuthError.misconfigured,
        'Google sign-in is not configured for this build',
      );
    }
    try {
      return await google.idToken();
    } on GoogleIdTokenException catch (e) {
      return switch (e.code) {
        GoogleIdTokenFailure.cancelled => const ForgeAuthCancelled(),
        GoogleIdTokenFailure.noAccount => ForgeAuthFailure(
          ForgeAuthError.noGoogleAccount,
          e.message,
        ),
        GoogleIdTokenFailure.unavailable => ForgeAuthFailure(
          ForgeAuthError.googleUnavailable,
          e.message,
        ),
        GoogleIdTokenFailure.misconfigured => ForgeAuthFailure(
          ForgeAuthError.misconfigured,
          e.message,
        ),
        GoogleIdTokenFailure.unknown => ForgeAuthFailure(
          ForgeAuthError.unknown,
          e.message,
        ),
      };
    }
  }

  @override
  Future<ForgeAuthResult> signUpWithEmail(String email, String password) =>
      _guard(() async {
        final response = await _auth.signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: _redirect,
        );
        if (response.session == null) {
          return ForgeAuthEmailSent(
            email.trim(),
            ForgeMailPurpose.confirmation,
          );
        }
        return _success(response.user);
      });

  @override
  Future<ForgeAuthResult> signInWithEmail(String email, String password) =>
      _guard(() async {
        final response = await _auth.signInWithPassword(
          email: email.trim(),
          password: password,
        );
        return _success(response.user);
      });

  @override
  Future<ForgeAuthResult> resendConfirmation(String email) => _guard(() async {
    await _auth.resend(
      email: email.trim(),
      type: sb.OtpType.signup,
      emailRedirectTo: _redirect,
    );
    return ForgeAuthEmailSent(email.trim(), ForgeMailPurpose.confirmation);
  });

  @override
  Future<ForgeAuthResult> sendPasswordReset(String email) => _guard(() async {
    await _auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect);
    return ForgeAuthEmailSent(email.trim(), ForgeMailPurpose.passwordReset);
  });

  @override
  Future<ForgeAuthResult> updatePassword(String newPassword) =>
      _guard(() async {
        final response = await _auth.updateUser(
          sb.UserAttributes(password: newPassword),
        );
        return _success(response.user);
      });

  @override
  Future<ForgeAuthResult> setPassword(String password) =>
      updatePassword(password);

  /// Runs a Supabase call and turns its exceptions into results.
  Future<ForgeAuthResult> _guard(
    Future<ForgeAuthResult> Function() body,
  ) async {
    try {
      return await body();
    } on sb.AuthException catch (e) {
      return ForgeAuthFailure(mapAuthException(e), describe(e));
    }
  }

  static ForgeAuthResult _success(sb.User? user) => user == null
      ? const ForgeAuthFailure(
          ForgeAuthError.unknown,
          'Supabase returned no user',
        )
      : ForgeAuthSuccess(ForgeSession.fromSupabase(user));

  /// The server's message, with weak-password reasons appended so the UI
  /// can say why.
  static String describe(sb.AuthException e) =>
      e is sb.AuthWeakPasswordException && e.reasons.isNotEmpty
      ? '${e.message} (${e.reasons.join(', ')})'
      : e.message;

  @override
  Future<void> signOut({bool everywhere = false}) async {
    await _auth.signOut(
      scope: everywhere ? sb.SignOutScope.global : sb.SignOutScope.local,
    );
    await _google?.signOut();
  }

  /// Supabase's state → ours. Pure, so it can be tested without a client.
  static ForgeAuthState mapState(sb.AuthState state) => ForgeAuthState(
    event: mapEvent(state.event),
    session: _session(state.session?.user),
  );

  static ForgeAuthEvent mapEvent(sb.AuthChangeEvent event) => switch (event) {
    sb.AuthChangeEvent.initialSession => ForgeAuthEvent.initial,
    sb.AuthChangeEvent.signedIn => ForgeAuthEvent.signedIn,
    sb.AuthChangeEvent.signedOut => ForgeAuthEvent.signedOut,
    sb.AuthChangeEvent.tokenRefreshed => ForgeAuthEvent.tokenRefreshed,
    sb.AuthChangeEvent.userUpdated => ForgeAuthEvent.userUpdated,
    sb.AuthChangeEvent.passwordRecovery => ForgeAuthEvent.passwordRecovery,
    _ => ForgeAuthEvent.other,
  };

  /// A Supabase auth error → ours, by exception type first and then by the
  /// server's error code
  /// (https://supabase.com/docs/guides/auth/debugging/error-codes).
  static ForgeAuthError mapAuthException(sb.AuthException e) {
    if (e is sb.AuthRetryableFetchException) return ForgeAuthError.network;
    if (e is sb.AuthWeakPasswordException) return ForgeAuthError.weakPassword;
    if (e is sb.AuthSessionMissingException) {
      return ForgeAuthError.sessionMissing;
    }
    return switch (e.code) {
      'invalid_credentials' => ForgeAuthError.invalidCredentials,
      'email_not_confirmed' => ForgeAuthError.emailNotConfirmed,
      'user_already_exists' || 'email_exists' => ForgeAuthError.emailTaken,
      'weak_password' => ForgeAuthError.weakPassword,
      'validation_failed' ||
      'email_address_invalid' => ForgeAuthError.invalidEmail,
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => ForgeAuthError.rateLimited,
      'otp_expired' ||
      'flow_state_expired' ||
      'flow_state_not_found' ||
      'bad_code_verifier' => ForgeAuthError.linkExpired,
      'same_password' => ForgeAuthError.samePassword,
      'session_missing' ||
      'session_not_found' ||
      'session_expired' => ForgeAuthError.sessionMissing,
      'identity_already_exists' => ForgeAuthError.identityAlreadyLinked,
      'single_identity_not_deletable' ||
      'email_conflict_identity_not_deletable' =>
        ForgeAuthError.lastSignInMethod,
      'signup_disabled' ||
      'email_provider_disabled' ||
      'provider_disabled' ||
      'manual_linking_disabled' => ForgeAuthError.misconfigured,
      _ => ForgeAuthError.unknown,
    };
  }

  static ForgeSession? _session(sb.User? user) =>
      user == null ? null : ForgeSession.fromSupabase(user);
}
