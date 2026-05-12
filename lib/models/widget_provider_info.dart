import 'dart:typed_data';

class WidgetProviderInfo {
  final String packageName;
  final String appName;
  final String providerClass;
  final String label;
  final int minWidth;
  final int minHeight;
  final int minResizeWidth;
  final int minResizeHeight;
  final Uint8List? appIcon;
  final Uint8List? previewImage;

  const WidgetProviderInfo({
    required this.packageName,
    required this.appName,
    required this.providerClass,
    required this.label,
    this.minWidth = 0,
    this.minHeight = 0,
    this.minResizeWidth = 0,
    this.minResizeHeight = 0,
    this.appIcon,
    this.previewImage,
  });

  static WidgetProviderInfo fromMap(Map map) {
    final preview = map['previewImage'];
    final appIcon = map['appIcon'];
    return WidgetProviderInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      providerClass: map['providerClass'] as String? ?? '',
      label: map['label'] as String? ?? '',
      minWidth: map['minWidth'] as int? ?? 0,
      minHeight: map['minHeight'] as int? ?? 0,
      minResizeWidth: map['minResizeWidth'] as int? ?? 0,
      minResizeHeight: map['minResizeHeight'] as int? ?? 0,
      appIcon: appIcon is Uint8List ? appIcon : null,
      previewImage: preview is Uint8List ? preview : null,
    );
  }
}
