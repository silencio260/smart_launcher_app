import 'package:characters/characters.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';

final _asciiSectionLetter = RegExp(r'^[A-Z]$');

sealed class DrawerItem {}

class SectionHeader extends DrawerItem {
  final String letter;
  SectionHeader(this.letter);
}

class AppRow extends DrawerItem {
  final List<AppInfo> apps;
  AppRow(this.apps);
}

List<DrawerItem> buildSections(List<AppInfo> apps, int columns) {
  final items = <DrawerItem>[];
  final favoriteApps =
      apps.where(LauncherFeatureCatalog.isFeatureApp).toList(growable: false);
  if (favoriteApps.isNotEmpty) {
    items.add(SectionHeader('Favorites'));
    for (var i = 0; i < favoriteApps.length; i += columns) {
      items.add(AppRow(
        favoriteApps.skip(i).take(columns).toList(growable: false),
      ));
    }
  }

  final sectionApps = apps
      .where((app) => !LauncherFeatureCatalog.isFeatureApp(app))
      .toList(growable: false);
  String? currentLetter;

  for (var i = 0; i < sectionApps.length;) {
    final app = sectionApps[i];
    final letter = _sectionLetter(app.name);

    if (letter != currentLetter) {
      currentLetter = letter;
      items.add(SectionHeader(letter));
    }

    final row = <AppInfo>[];
    while (i < sectionApps.length) {
      final a = sectionApps[i];
      final l = _sectionLetter(a.name);
      if (l != currentLetter || row.length >= columns) break;
      row.add(a);
      i++;
    }
    items.add(AppRow(row));
  }

  return items;
}

String _sectionLetter(String name) {
  final chars = name.trim().characters;
  if (chars.isEmpty) return '#';
  final upper = chars.first.toUpperCase();
  return _asciiSectionLetter.hasMatch(upper) ? upper : '#';
}
