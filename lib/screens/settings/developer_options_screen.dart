import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_settings.dart';
import '../../state/settings_cubit.dart';

class DeveloperOptionsScreen extends StatelessWidget {
  const DeveloperOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SettingsCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Options')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        bloc: cubit,
        builder: (context, state) {
          return ListView(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.bug_report_outlined),
                title: const Text('Grid Debug Overlay'),
                subtitle: const Text(
                  'Show free cells in green and blocked or occupied cells in red',
                ),
                value: state.showGridDebugOverlay,
                onChanged: (value) => cubit.update(
                  state.copyWith(showGridDebugOverlay: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.article_outlined),
                title: const Text('Widget Debug Logs'),
                subtitle: const Text(
                  'Print widget sizing/resize/binding logs to logcat and the Dart console',
                ),
                value: state.showWidgetDebugLogs,
                onChanged: (value) => cubit.update(
                  state.copyWith(showWidgetDebugLogs: value),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.info_outline),
                title: const Text('Widget Picker Debug Info'),
                subtitle: const Text(
                  'Show min/max spans, dp sizes, and resize mode under each widget in the picker',
                ),
                value: state.showWidgetPickerDebugInfo,
                onChanged: (value) => cubit.update(
                  state.copyWith(showWidgetPickerDebugInfo: value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
