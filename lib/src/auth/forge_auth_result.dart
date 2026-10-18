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
  unknown,
}

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
