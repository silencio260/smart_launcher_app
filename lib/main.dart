import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'models/launcher_settings.dart';
import 'state/apps_cubit.dart';
import 'state/launcher_cubit.dart';
import 'state/search_cubit.dart';
import 'state/settings_cubit.dart';
import 'state/workspace_cubit.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const SmartLauncherApp());
}

class SmartLauncherApp extends StatelessWidget {
  const SmartLauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsCubit()..load()),
        BlocProvider(create: (_) => AppsCubit()..loadCachedThenRefresh()),
        BlocProvider(create: (_) => WorkspaceCubit()..loadLayout()),
        BlocProvider(create: (_) => LauncherCubit()),
        BlocProvider(create: (_) => SearchCubit()),
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
            title: 'Smart Launcher',
            debugShowCheckedModeBanner: false,
            themeMode: themeMode,
            color: Colors.transparent,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: Colors.transparent,
              canvasColor: Colors.transparent,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.indigo,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              scaffoldBackgroundColor: Colors.transparent,
              canvasColor: Colors.transparent,
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
