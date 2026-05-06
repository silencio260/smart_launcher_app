import 'dart:typed_data';

class AppInfo {
  final String name;
  final String packageName;
  final Uint8List? icon;

  const AppInfo({
    required this.name,
    required this.packageName,
    this.icon,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      name: map['name'] as String? ?? map['packageName'] as String,
      packageName: map['packageName'] as String,
      icon: map['icon'] != null ? Uint8List.fromList(List<int>.from(map['icon'] as List)) : null,
    );
  }
}
