import 'package:flutter/material.dart';
import 'package:smart_launcher_app/core/models/launcher_settings.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/smartspace/date_time_widget.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/smartspace/smartspace_card.dart';

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
