import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/config/theme_manager.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/core/utils/app_strings.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/launcher_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/screens/home_screen.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/route_coverage_scope.dart';
import 'package:smart_launcher_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/launcher_feature_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

/// Root widget: provides the app-wide Cubits (resolved from the GetIt service
/// locator) and configures `MaterialApp`.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<SettingsCubit>()..load()),
        BlocProvider(create: (_) => sl<LauncherFeatureSettingsCubit>()..load()),
        BlocProvider(create: (_) => sl<AppsCubit>()..loadCachedThenRefresh()),
        BlocProvider(create: (_) => sl<WorkspaceCubit>()..loadLayout()),
        BlocProvider(create: (_) => sl<LauncherCubit>()),
        BlocProvider(create: (_) => sl<SearchCubit>()),
      ],
      child: BlocBuilder<SettingsCubit, LauncherSettings>(
        buildWhen: (prev, next) => prev.themeMode != next.themeMode,
        builder: (context, settings) {
          final themeMode = switch (settings.themeMode) {
            ThemeMode2.light => ThemeMode.light,
            ThemeMode2.dark => ThemeMode.dark,
            ThemeMode2.system => ThemeMode.system,
          };
          return MaterialApp(
            title: AppStrings.appName,
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            color: Colors.transparent,
            navigatorObservers: [homeRouteObserver],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
