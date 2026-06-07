import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/launcher_state.dart';

class LauncherCubit extends Cubit<LauncherState> {
  LauncherCubit() : super(LauncherState.normal);

  void goToState(LauncherState s) => emit(s);

  void toggleAllApps() => emit(
        state == LauncherState.allApps
            ? LauncherState.normal
            : LauncherState.allApps,
      );

  void enterEditMode() => emit(LauncherState.editMode);

  void exitEditMode() => emit(LauncherState.normal);

  void openFolder() => emit(LauncherState.springLoaded);

  void closeFolder() => emit(LauncherState.normal);
}
