import 'package:flutter/material.dart';

class RecentsSettingsScreen extends StatelessWidget {
  const RecentsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recents')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.history),
            title: Text('Recent Apps'),
            subtitle: Text(
              'Recents behavior is managed by the system. '
              'Use gestures to configure how recents are triggered.',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}
