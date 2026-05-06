import 'package:flutter/material.dart';
import '../../models/launcher_settings.dart';
import 'date_time_widget.dart';
import 'smartspace_card.dart';

class SmartspaceView extends StatelessWidget {
  final LauncherSettings settings;

  const SmartspaceView({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DateTimeWidget(settings: settings),
        const SizedBox(height: 8),
        const SmartspaceCard(),
      ],
    );
  }
}
