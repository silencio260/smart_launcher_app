import 'dart:typed_data';

class IconPackInfo {
  final String packageName;
  final String label;
  final Uint8List? icon;

  const IconPackInfo({
    required this.packageName,
    required this.label,
    this.icon,
  });

  factory IconPackInfo.fromMap(Map<dynamic, dynamic> map) {
    return IconPackInfo(
      packageName: map['packageName'] as String,
      label: map['label'] as String,
      icon: map['icon'] != null
          ? Uint8List.fromList(List<int>.from(map['icon'] as List))
          : null,
    );
  }
}
