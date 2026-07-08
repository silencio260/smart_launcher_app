import 'package:dartz/dartz.dart';
import 'package:smart_launcher_app/core/error/error_handler.dart';
import 'package:smart_launcher_app/core/error/failure.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/features/apps/domain/repositories/apps_base_repo.dart';

/// [AppsBaseRepo] implementation over the native [LauncherService] platform
/// gateway. Each fallible platform call is converted to a [Failure] via
/// [ErrorHandler.handle].
class AppsRepo implements AppsBaseRepo {
  const AppsRepo();

  @override
  Future<Either<Failure, AppListRefresh>> refreshInstalledApps({
    String? knownSnapshotKey,
  }) async {
    try {
      final refresh = await LauncherService.refreshInstalledApps(
        knownSnapshotKey: knownSnapshotKey,
      );
      return Right(refresh);
    } catch (error) {
      return Left(ErrorHandler.handle(error));
    }
  }

  @override
  Future<Either<Failure, List<AppInfo>>> getInstalledApps() async {
    try {
      final apps = await LauncherService.getInstalledApps();
      return Right(apps);
    } catch (error) {
      return Left(ErrorHandler.handle(error));
    }
  }
}
