import 'package:flutter/material.dart';

import '../../../data/mini_app_repositories.dart';
import '../../../data/world_cities.dart';
import '../mini_app_chrome.dart';

/// Searchable picker over the curated [worldCities] list. Tapping a city adds
/// it to the World Clock (offline, DST-correct) and pops. Already-added cities
/// are marked.
class WorldClockPickerScreen extends StatefulWidget {
  final ClockRepository repo;

  const WorldClockPickerScreen({super.key, required this.repo});

  @override
  State<WorldClockPickerScreen> createState() => _WorldClockPickerScreenState();
}

class _WorldClockPickerScreenState extends State<WorldClockPickerScreen> {
  String _query = '';

  List<WorldCity> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? worldCities
        : worldCities
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.country.toLowerCase().contains(q) ||
                c.zoneId.toLowerCase().contains(q))
            .toList();
    return list;
  }

  Future<void> _add(WorldCity city) async {
    await widget.repo.addCity(city);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cities = _filtered;
    return MiniAppScaffold(
      title: 'Add city',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search city or country',
                prefixIcon: const Icon(Icons.search, color: miniAppMuted),
                filled: true,
                fillColor: miniAppSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: cities.length,
              itemBuilder: (context, index) {
                final city = cities[index];
                final added = widget.repo.hasCity(city.zoneId);
                return ListTile(
                  title: Text(city.name),
                  subtitle: Text(city.country,
                      style: const TextStyle(color: miniAppMuted)),
                  trailing: added
                      ? const Icon(Icons.check, color: Colors.white)
                      : const Icon(Icons.add, color: miniAppMuted),
                  onTap: added ? null : () => _add(city),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
