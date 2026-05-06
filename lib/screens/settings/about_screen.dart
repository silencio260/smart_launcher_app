import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          const SizedBox(height: 32),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.rocket_launch,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Smart Launcher',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          const Center(
            child: Text(
              'by GENREVIBES TECHNOLOGIES INC',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          const SizedBox(height: 32),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            trailing: Text('1.0.0'),
          ),
          const ListTile(
            leading: Icon(Icons.code),
            title: Text('Built with Flutter'),
            trailing: Text('3.x'),
          ),
          const ListTile(
            leading: Icon(Icons.favorite_outline),
            title: Text('Inspired by Lawnchair'),
            subtitle: Text('Open-source Android launcher'),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.bug_report_outlined),
            title: Text('Report a Bug'),
          ),
          const ListTile(
            leading: Icon(Icons.star_outline),
            title: Text('Rate on Play Store'),
          ),
        ],
      ),
    );
  }
}
