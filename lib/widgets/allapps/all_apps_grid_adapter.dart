import 'package:characters/characters.dart';
import '../../models/app_info.dart';

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
  String? currentLetter;

  for (var i = 0; i < apps.length;) {
    final app = apps[i];
    final letter = _sectionLetter(app.name);

    if (letter != currentLetter) {
      currentLetter = letter;
      items.add(SectionHeader(letter));
    }

    final row = <AppInfo>[];
    while (i < apps.length) {
      final a = apps[i];
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
