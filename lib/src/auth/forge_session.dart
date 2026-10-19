import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'forge_auth_result.dart';

/// How a sign-in method reached the account.
enum ForgeIdentityProvider {
  google,
  email,
  apple,

  /// Anything else Supabase reports (phone, another OAuth provider).
  other;

  /// Maps Supabase's provider name (`google`, `email`, `apple`, …).
  static ForgeIdentityProvider fromName(String name) =>
      switch (name.toLowerCase()) {
        'google' => google,
        'email' => email,
        'apple' => apple,
        _ => other,
      };
}

/// One linked sign-in method of an account.
@immutable
class ForgeIdentity {
  const ForgeIdentity({
    required this.id,
    required this.identityId,
    required this.provider,
    this.email,
  });

  /// The provider's id for the user (Google's `sub`, the email address…).
  final String id;

  /// Supabase's own id for this link; what unlinking refers to.
  final String identityId;
  final ForgeIdentityProvider provider;

  /// The email that provider knows the user by, when it reports one.
  final String? email;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeIdentity &&
          other.id == id &&
          other.identityId == identityId &&
          other.provider == provider &&
          other.email == email;

  @override
  int get hashCode => Object.hash(id, identityId, provider, email);

  @override
  String toString() => 'ForgeIdentity(${provider.name}, $email)';
}

/// The signed-in user as the app sees it. No Supabase types leak out.
@immutable
class ForgeSession {
  const ForgeSession({
    required this.userId,
    this.email,
    this.emailConfirmed = false,
    this.identities = const [],
    this.createdAt,
  });

  /// Plain-type view of a Supabase user.
  factory ForgeSession.fromSupabase(sb.User user) => ForgeSession(
    userId: user.id,
    email: user.email,
    emailConfirmed: user.emailConfirmedAt != null,
    identities: [
      for (final i in user.identities ?? const <sb.UserIdentity>[])
        ForgeIdentity(
          id: i.id,
          identityId: i.identityId,
          provider: ForgeIdentityProvider.fromName(i.provider),
          email: i.identityData?['email'] as String?,
        ),
    ],
    createdAt: DateTime.tryParse(user.createdAt)?.toUtc(),
  );

  /// The account id (`auth.users.id`, also `accounts.id`).
  final String userId;

  /// The account's primary email; null for a user with none yet.
  final String? email;

  /// Whether the address was confirmed (email sign-ups start unconfirmed).
  final bool emailConfirmed;
  final List<ForgeIdentity> identities;

  /// When the account was created, UTC.
  final DateTime? createdAt;

  bool has(ForgeIdentityProvider provider) =>
      identities.any((i) => i.provider == provider);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeSession &&
          other.userId == userId &&
          other.email == email &&
          other.emailConfirmed == emailConfirmed &&
          listEquals(other.identities, identities) &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    userId,
    email,
    emailConfirmed,
    Object.hashAll(identities),
    createdAt,
  );

  @override
  String toString() => 'ForgeSession($userId, $email)';
}

/// What just happened to the session.
enum ForgeAuthEvent {
  /// The state as found at start (or when a listener attached).
  initial,
  signedIn,
  signedOut,
  tokenRefreshed,
  userUpdated,

  /// The app was opened from a password-reset link: show "set a new
  /// password" (the session is temporary until the password is set).
  passwordRecovery,

  /// A confirmation or reset link opened the app but could not be
  /// verified (expired, already used, malformed); [ForgeAuthState.error]
  /// says why and the session is unchanged. Show copy and offer "send
  /// again".
  mailLinkFailed,
  other,
}

/// A session (or none) plus the event that produced it.
@immutable
class ForgeAuthState {
  const ForgeAuthState({required this.event, this.session, this.error});

  /// The state before anyone ever signed in.
  static const signedOut = ForgeAuthState(event: ForgeAuthEvent.initial);

  final ForgeAuthEvent event;
  final ForgeSession? session;

  /// Why a [ForgeAuthEvent.mailLinkFailed] happened; null otherwise.
  final ForgeAuthError? error;

  bool get isSignedIn => session != null;
  bool get isPasswordRecovery => event == ForgeAuthEvent.passwordRecovery;
  bool get isMailLinkFailed => event == ForgeAuthEvent.mailLinkFailed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeAuthState &&
          other.event == event &&
          other.session == session &&
          other.error == error;

  @override
  int get hashCode => Object.hash(event, session, error);

  @override
  String toString() =>
      'ForgeAuthState(${event.name}, $session${error == null ? '' : ', ${error!.name}'})';
}
