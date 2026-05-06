import '../../models/app_info.dart';

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
  final visible = apps.where((a) => !a.isHidden).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final items = <DrawerItem>[];
  String? currentLetter;

  for (var i = 0; i < visible.length;) {
    final app = visible[i];
    final letter = app.name.isNotEmpty ? app.name[0].toUpperCase() : '#';

    if (letter != currentLetter) {
      currentLetter = letter;
      items.add(SectionHeader(letter));
    }

    final row = <AppInfo>[];
    while (i < visible.length) {
      final a = visible[i];
      final l = a.name.isNotEmpty ? a.name[0].toUpperCase() : '#';
      if (l != currentLetter || row.length >= columns) break;
      row.add(a);
      i++;
    }
    items.add(AppRow(row));
  }

  return items;
}
