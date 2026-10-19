import 'package:flutter/foundation.dart';

/// Why a data call failed, in terms the UI can explain.
enum ForgeDataError {
  /// Nobody is signed in.
  sessionMissing,

  /// The account is pending deletion; writes are refused.
  accountInactive,

  /// The server rejected the value (too long, wrong shape).
  invalid,

  /// Could not reach the backend.
  network,
  unknown,
}

/// The outcome of a data call: a value or a typed failure. Never thrown.
@immutable
sealed class ForgeResult<T> {
  const ForgeResult();
}

class ForgeOk<T> extends ForgeResult<T> {
  const ForgeOk(this.value);
  final T value;

  @override
  bool operator ==(Object other) => other is ForgeOk<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ForgeOk($value)';
}

class ForgeFailed<T> extends ForgeResult<T> {
  const ForgeFailed(this.error, this.message);
  final ForgeDataError error;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ForgeFailed<T> &&
      other.error == error &&
      other.message == message;

  @override
  int get hashCode => Object.hash(error, message);

  @override
  String toString() => 'ForgeFailed(${error.name}, $message)';
}
