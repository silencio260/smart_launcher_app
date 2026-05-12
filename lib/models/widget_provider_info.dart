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
  final int maxResizeWidth;
  final int maxResizeHeight;
  final int targetCellWidth;
  final int targetCellHeight;
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
    this.maxResizeWidth = 0,
    this.maxResizeHeight = 0,
    this.targetCellWidth = 0,
    this.targetCellHeight = 0,
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
      maxResizeWidth: map['maxResizeWidth'] as int? ?? 0,
      maxResizeHeight: map['maxResizeHeight'] as int? ?? 0,
      targetCellWidth: map['targetCellWidth'] as int? ?? 0,
      targetCellHeight: map['targetCellHeight'] as int? ?? 0,
      appIcon: appIcon is Uint8List ? appIcon : null,
      previewImage: preview is Uint8List ? preview : null,
    );
  }
}
