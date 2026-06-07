import 'package:dartz/dartz.dart';
import 'package:smart_launcher_app/core/error/failure.dart';

/// Abstract base class for use cases.
///
/// Per the pragmatic-adaptation decision for this launcher, use cases are added
/// only where an operation has real branching logic worth isolating; most
/// repository methods are thin pass-throughs and are called directly. Where a
/// use case *is* warranted, extend this.
abstract class BaseUseCase<Output, Input> {
  Future<Either<Failure, Output>> call(Input params);
}

/// Marker for use cases that take no parameters.
class NoParams {
  const NoParams();
}
