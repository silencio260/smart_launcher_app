import 'package:flutter/services.dart';
import 'package:smart_launcher_app/core/error/failure.dart';

/// Centralised exception -> [Failure] conversion.
///
/// Repositories call [ErrorHandler.handle] in their `catch` blocks so the
/// presentation layer only ever deals with domain [Failure]s, never raw
/// platform exceptions.
class ErrorHandler {
  const ErrorHandler._();

  static Failure handle(Object error) {
    if (error is Failure) return error;
    if (error is PlatformException) {
      return PlatformChannelFailure(error.message ?? 'Platform call failed');
    }
    if (error is MissingPluginException) {
      return PlatformChannelFailure(error.message ?? 'Missing platform plugin');
    }
    return UnexpectedFailure(error.toString());
  }
}
