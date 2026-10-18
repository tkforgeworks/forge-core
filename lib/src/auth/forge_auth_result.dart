import 'package:flutter/foundation.dart';

import 'forge_session.dart';

/// Why a sign-in or account call failed, in terms the UI can explain. The
/// email flows (FC-5) add their own values.
enum ForgeAuthError {
  /// The device has no Google account to offer.
  noGoogleAccount,

  /// Google's sign-in UI could not be shown (no Play services, or it is
  /// busy).
  googleUnavailable,

  /// The build is missing configuration (no web client ID, no client set
  /// up for this signing key, provider off in Supabase).
  misconfigured,

  /// Could not reach the backend.
  network,

  // Email and password (FC-5).
  /// Wrong email or password (Supabase does not say which).
  invalidCredentials,

  /// The account exists but its address was never confirmed.
  emailNotConfirmed,

  /// Sign-up with an address that already has an account.
  emailTaken,

  /// Too short, or on the leaked-password list; [ForgeAuthFailure.message]
  /// carries the server's reasons.
  weakPassword,

  /// The address did not pass the server's validation.
  invalidEmail,

  /// Too many emails or requests for now.
  rateLimited,

  /// The confirmation or reset link is expired or was already used.
  linkExpired,

  /// The new password equals the old one.
  samePassword,

  /// A call that needs a signed-in user ran without one (for example
  /// setting a password from a stale reset link).
  sessionMissing,

  // Identity linking (FC-6).
  /// That Google account (or address) already belongs to another user.
  identityAlreadyLinked,

  /// Unlinking refused: it is the account's only way to sign in.
  lastSignInMethod,
  unknown,
}

/// Which mail [ForgeAuthEmailSent] refers to.
enum ForgeMailPurpose { confirmation, passwordReset }

/// The outcome of a sign-in attempt.
@immutable
sealed class ForgeAuthResult {
  const ForgeAuthResult();
}

/// Signed in; [session] is the account as the app sees it.
class ForgeAuthSuccess extends ForgeAuthResult {
  const ForgeAuthSuccess(this.session);
  final ForgeSession session;

  @override
  bool operator ==(Object other) =>
      other is ForgeAuthSuccess && other.session == session;

  @override
  int get hashCode => session.hashCode;

  @override
  String toString() => 'ForgeAuthSuccess($session)';
}

/// Nothing more can happen until the user opens an email: a sign-up that
/// needs confirmation, a resent confirmation, or a password-reset link.
class ForgeAuthEmailSent extends ForgeAuthResult {
  const ForgeAuthEmailSent(this.email, this.purpose);
  final String email;
  final ForgeMailPurpose purpose;

  @override
  bool operator ==(Object other) =>
      other is ForgeAuthEmailSent &&
      other.email == email &&
      other.purpose == purpose;

  @override
  int get hashCode => Object.hash(email, purpose);

  @override
  String toString() => 'ForgeAuthEmailSent($email, ${purpose.name})';
}

/// The user backed out; nothing to show.
class ForgeAuthCancelled extends ForgeAuthResult {
  const ForgeAuthCancelled();

  @override
  bool operator ==(Object other) => other is ForgeAuthCancelled;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'ForgeAuthCancelled()';
}

/// Failed for [error]; [message] is the backend's or the plugin's wording,
/// for logs. Apps show their own copy per [error].
class ForgeAuthFailure extends ForgeAuthResult {
  const ForgeAuthFailure(this.error, this.message);
  final ForgeAuthError error;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ForgeAuthFailure &&
      other.error == error &&
      other.message == message;

  @override
  int get hashCode => Object.hash(error, message);

  @override
  String toString() => 'ForgeAuthFailure(${error.name}, $message)';
}
