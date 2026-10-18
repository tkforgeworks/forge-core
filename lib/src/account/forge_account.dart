import 'package:flutter/foundation.dart';

/// The signed-in user's row in `accounts`: what the account page shows
/// beyond the session itself.
@immutable
class ForgeAccount {
  const ForgeAccount({
    required this.userId,
    this.username,
    required this.createdAt,
    this.deletionRequestedAt,
  });

  factory ForgeAccount.fromJson(Map<String, dynamic> json) => ForgeAccount(
    userId: json['id'] as String,
    username: json['username'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    deletionRequestedAt: json['deletion_requested_at'] == null
        ? null
        : DateTime.parse(json['deletion_requested_at'] as String).toUtc(),
  );

  final String userId;

  /// Set by the user from the account page; never prefilled.
  final String? username;

  /// When the account was created, UTC ("member since").
  final DateTime createdAt;

  /// Non-null once deletion was requested; the purge removes the row.
  final DateTime? deletionRequestedAt;

  bool get isPendingDeletion => deletionRequestedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeAccount &&
          other.userId == userId &&
          other.username == username &&
          other.createdAt == createdAt &&
          other.deletionRequestedAt == deletionRequestedAt;

  @override
  int get hashCode =>
      Object.hash(userId, username, createdAt, deletionRequestedAt);

  @override
  String toString() => 'ForgeAccount($userId, $username)';
}
