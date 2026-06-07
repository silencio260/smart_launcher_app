import 'package:dartz/dartz.dart';
import 'package:smart_launcher_app/core/error/failure.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';

/// Domain boundary for reading the device's installed-app catalogue.
///
/// Wraps the platform (`MethodChannel`) launcher host so the presentation layer
/// (AppsCubit) deals only with [Either]<[Failure], T>, never raw
/// `PlatformException`s. This is the canonical example of the
/// pragmatic-adaptation pattern for this launcher: the "remote" data source of
/// the reference architecture is replaced by a native platform data source.
abstract class AppsBaseRepo {
  /// Cheap delta check against a known snapshot key; returns the changed set or
  /// a flag that nothing changed.
  Future<Either<Failure, AppListRefresh>> refreshInstalledApps({
    String? knownSnapshotKey,
  });

  /// Full enumeration of installed launchable apps.
  Future<Either<Failure, List<AppInfo>>> getInstalledApps();
}
