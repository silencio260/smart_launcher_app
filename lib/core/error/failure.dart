import 'package:equatable/equatable.dart';

/// Domain-level error representation.
///
/// This is a *local-first* launcher (Hive + platform `MethodChannel`, almost no
/// network), so the failure taxonomy is adapted from the GenRevibes reference
/// architecture to the IO boundaries that actually exist here: platform
/// channels, local storage, and runtime permissions.
abstract class Failure extends Equatable {
  final String message;

  const Failure(this.message);

  @override
  List<Object?> get props => [message];
}

/// A `MethodChannel` call into the native Android launcher host failed.
class PlatformChannelFailure extends Failure {
  const PlatformChannelFailure([super.message = 'Platform call failed']);
}

/// Local persistence (Hive / SharedPreferences / file IO) failed.
class StorageFailure extends Failure {
  const StorageFailure([super.message = 'Local storage operation failed']);
}

/// A required runtime permission was denied or is unavailable.
class PermissionFailure extends Failure {
  const PermissionFailure([super.message = 'Required permission not granted']);
}

/// Catch-all for anything not otherwise classified.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unexpected error occurred']);
}
