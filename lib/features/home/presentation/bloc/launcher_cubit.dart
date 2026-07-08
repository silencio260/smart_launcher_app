import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/analytics/app_events.dart';
import 'package:smart_launcher_app/core/models/launcher_state.dart';

class LauncherCubit extends Cubit<LauncherState> {
  LauncherCubit() : super(LauncherState.normal);

  void goToState(LauncherState s) {
    if (s == LauncherState.allApps && state != LauncherState.allApps) {
      AppAnalytics.drawerOpened(openMethod: 'swipe');
    }
    emit(s);
  }

  void toggleAllApps() {
    final opening = state != LauncherState.allApps;
    if (opening) AppAnalytics.drawerOpened(openMethod: 'tap');
    emit(opening ? LauncherState.allApps : LauncherState.normal);
  }

  void enterEditMode() {
    AppAnalytics.homeEditMode();
    emit(LauncherState.editMode);
  }

  void exitEditMode() => emit(LauncherState.normal);

  void openFolder() {
    AppAnalytics.folderOpened();
    emit(LauncherState.springLoaded);
  }

  void closeFolder() => emit(LauncherState.normal);
}
