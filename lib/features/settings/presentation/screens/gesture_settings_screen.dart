import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';

class GestureSettingsScreen extends StatelessWidget {
  const GestureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestures')),
      body: BlocBuilder<SettingsCubit, LauncherSettings>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return ListView(
            children: [
              _GestureTile(
                icon: Icons.touch_app,
                label: 'Double Tap',
                current: s.doubleTapAction,
                onPick: (a) => cubit.update(s.copyWith(doubleTapAction: a)),
              ),
              _GestureTile(
                icon: Icons.swipe_up,
                label: 'Swipe Up',
                current: s.swipeUpAction,
                onPick: (a) => cubit.update(s.copyWith(swipeUpAction: a)),
              ),
              _GestureTile(
                icon: Icons.swipe_down,
                label: 'Swipe Down',
                current: s.swipeDownAction,
                onPick: (a) => cubit.update(s.copyWith(swipeDownAction: a)),
              ),
              _GestureTile(
                icon: Icons.swipe_up_alt,
                label: 'Two-Finger Swipe Up',
                current: s.twoFingerSwipeUpAction,
                onPick: (a) =>
                    cubit.update(s.copyWith(twoFingerSwipeUpAction: a)),
              ),
              _GestureTile(
                icon: Icons.swipe_down_alt,
                label: 'Two-Finger Swipe Down',
                current: s.twoFingerSwipeDownAction,
                onPick: (a) =>
                    cubit.update(s.copyWith(twoFingerSwipeDownAction: a)),
              ),
              _GestureTile(
                icon: Icons.home_outlined,
                label: 'Home Button',
                current: s.homeBtnAction,
                onPick: (a) => cubit.update(s.copyWith(homeBtnAction: a)),
              ),
              _GestureTile(
                icon: Icons.arrow_back,
                label: 'Back Button',
                current: s.backBtnAction,
                onPick: (a) => cubit.update(s.copyWith(backBtnAction: a)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GestureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final GestureAction current;
  final ValueChanged<GestureAction> onPick;

  const _GestureTile({
    required this.icon,
    required this.label,
    required this.current,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(_actionLabel(current)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPicker(context),
    );
  }

  String _actionLabel(GestureAction a) => switch (a) {
        GestureAction.none => 'None',
        GestureAction.openDrawer => 'Open App Drawer',
        GestureAction.openSearch => 'Open Search',
        GestureAction.openNotifications => 'Open Notifications',
        GestureAction.openQuickSettings => 'Open Quick Settings',
        GestureAction.sleepScreen => 'Sleep Screen',
        GestureAction.openRecents => 'Open Recents',
        GestureAction.openAssistant => 'Open Assistant',
        GestureAction.openCamera => 'Open Camera',
        GestureAction.openSettings => 'Open Launcher Settings',
      };

  void _showPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(label),
        // sleepScreen and openRecents are intentionally excluded: they required
        // the accessibility service (BIND_ACCESSIBILITY_SERVICE), which has been
        // removed to avoid Play-policy rejection. The enum values are kept for
        // backward-compat with any persisted prefs, just not offered here.
        children: GestureAction.values
            .where((a) =>
                a != GestureAction.sleepScreen && a != GestureAction.openRecents)
            .map((a) => ListTile(
                  leading: Icon(
                    current == a
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: current == a
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(_actionLabel(a)),
                  onTap: () {
                    onPick(a);
                    Navigator.pop(context);
                  },
                ))
            .toList(),
      ),
    );
  }
}
