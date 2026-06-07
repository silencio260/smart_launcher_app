import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/bloc_observer.dart';
import 'package:smart_launcher_app/container_injector.dart';
import 'package:smart_launcher_app/core/storage/feature_hive_store.dart';
import 'package:smart_launcher_app/features/clock/data/clock_service.dart';
import 'package:smart_launcher_app/my_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();
  initApp();
  await FeatureHiveStore.init();
  await ClockService.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));
  runApp(const MyApp());
}
