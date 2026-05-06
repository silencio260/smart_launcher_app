import 'dart:typed_data';

class ShortcutInfo {
  final String id;
  final String packageName;
  final String shortLabel;
  final String? longLabel;
  final Uint8List? icon;

  const ShortcutInfo({
    required this.id,
    required this.packageName,
    required this.shortLabel,
    this.longLabel,
    this.icon,
  });

  factory ShortcutInfo.fromMap(Map<dynamic, dynamic> map) {
    return ShortcutInfo(
      id: map['id'] as String,
      packageName: map['packageName'] as String,
      shortLabel: map['shortLabel'] as String? ?? '',
      longLabel: map['longLabel'] as String?,
      icon: map['icon'] != null
          ? Uint8List.fromList(List<int>.from(map['icon'] as List))
          : null,
    );
  }
}
