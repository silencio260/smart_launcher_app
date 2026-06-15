import 'package:flutter/material.dart';

class SearchSettingsScreen extends StatelessWidget {
  const SearchSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.apps),
            title: Text('App Search'),
            subtitle: Text('Always enabled'),
            trailing: Icon(Icons.check, color: Colors.green),
          ),
          ListTile(
            leading: Icon(Icons.calculate_outlined),
            title: Text('Calculator'),
            subtitle: Text('Evaluate math expressions inline'),
            trailing: Icon(Icons.check, color: Colors.green),
          ),
          ListTile(
            leading: Icon(Icons.public),
            title: Text('Web Search'),
            subtitle: Text('Opens Google in browser'),
            trailing: Icon(Icons.check, color: Colors.green),
          ),
          // Contact Search removed: the feature was never wired (no Dart caller
          // for the contacts channel), and READ_CONTACTS has been dropped.
        ],
      ),
    );
  }
}
