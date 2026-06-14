import 'package:get_it/get_it.dart';
import 'package:smart_launcher_app/features/apps/data/repositories/apps_repo.dart';
import 'package:smart_launcher_app/features/apps/domain/repositories/apps_base_repo.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/launcher_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/onboarding/presentation/bloc/onboarding_cubit.dart';
import 'package:smart_launcher_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// Service locator singleton.
final GetIt sl = GetIt.instance;

/// App-wide DI entry point. Called once from `main()` before `runApp`.
///
/// Convention (per ARCHITECTURE_ANALYSIS.md):
///   * Cubits/Blocs       -> `registerFactory`   (stateful, recreated)
///   * Repositories/      -> `registerLazySingleton`
///     data sources/services
///
/// Note: many platform/storage services in this launcher are still static
/// utility classes (e.g. `LauncherService`, `FeatureHiveStore`). They are
/// migrated to injectable singletons opportunistically during the repository
/// pass; until then `initCore` stays intentionally light.
void initApp() {
  initCore();
  initApps();
  initHome();
  initSearch();
  initSettings();
  initOnboarding();
}

/// Shared, cross-feature singletons (repositories/services).
void initCore() {
  // Populated as static services are migrated to injectable singletons.
}

void initApps() {
  sl.registerLazySingleton<AppsBaseRepo>(() => const AppsRepo());
  sl.registerFactory<AppsCubit>(() => AppsCubit(repo: sl()));
}

void initHome() {
  sl.registerFactory<WorkspaceCubit>(() => WorkspaceCubit());
  sl.registerFactory<LauncherCubit>(() => LauncherCubit());
}

void initSearch() {
  sl.registerFactory<SearchCubit>(() => SearchCubit());
}

void initSettings() {
  sl.registerFactory<SettingsCubit>(() => SettingsCubit());
  sl.registerFactory<LauncherFeatureSettingsCubit>(
    () => LauncherFeatureSettingsCubit(),
  );
}

void initOnboarding() {
  sl.registerFactory<OnboardingCubit>(() => OnboardingCubit());
}
