import 'package:flutter/foundation.dart';

/// One row of an app's `entries` table, typed by the app's [T].
@immutable
class ForgeEntry<T> {
  const ForgeEntry({
    required this.id,
    required this.data,
    required this.updatedAt,
    this.createdAt,
    this.deletedAt,
  });

  /// The app's own UUID for the row.
  final String id;

  /// The app's value; `null` for a tombstone (the row's data is `{}`).
  final T? data;

  /// The device's last-change time (UTC); the newest wins.
  final DateTime updatedAt;

  /// Set by the server on first insert; null on a row the app has not
  /// pushed yet.
  final DateTime? createdAt;

  /// Set when the entry was deleted.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeEntry<T> &&
          other.id == id &&
          other.data == data &&
          other.updatedAt == updatedAt &&
          other.createdAt == createdAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, data, updatedAt, createdAt, deletedAt);

  @override
  String toString() =>
      'ForgeEntry($id, ${isDeleted ? 'deleted' : data}, $updatedAt)';
}

/// What the sync's manifest listing returns per row: enough to decide which
/// rows to fetch and which local rows to delete, without the data.
@immutable
class ForgeEntryKey {
  const ForgeEntryKey({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
  });

  factory ForgeEntryKey.fromJson(Map<String, dynamic> json) => ForgeEntryKey(
    id: json['id'] as String,
    updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
    deletedAt: json['deleted_at'] == null
        ? null
        : DateTime.parse(json['deleted_at'] as String).toUtc(),
  );

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForgeEntryKey &&
          other.id == id &&
          other.updatedAt == updatedAt &&
          other.deletedAt == deletedAt;

  @override
  int get hashCode => Object.hash(id, updatedAt, deletedAt);

  @override
  String toString() =>
      'ForgeEntryKey($id, $updatedAt${isDeleted ? ', deleted' : ''})';
}
