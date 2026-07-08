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
  final int resizeMode;
  final int targetCellWidth;
  final int targetCellHeight;
  final int minSpanX;
  final int minSpanY;
  final int spanX;
  final int spanY;
  final int maxSpanX;
  final int maxSpanY;
  final Uint8List? appIcon;
  final Uint8List? previewImage;
  final bool previewIsGenerated;

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
    this.resizeMode = 3,
    this.targetCellWidth = 0,
    this.targetCellHeight = 0,
    this.minSpanX = 1,
    this.minSpanY = 1,
    this.spanX = 2,
    this.spanY = 1,
    this.maxSpanX = 5,
    this.maxSpanY = 6,
    this.appIcon,
    this.previewImage,
    this.previewIsGenerated = false,
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
      resizeMode: map['resizeMode'] as int? ?? 3,
      targetCellWidth: map['targetCellWidth'] as int? ?? 0,
      targetCellHeight: map['targetCellHeight'] as int? ?? 0,
      minSpanX: map['minSpanX'] as int? ?? 1,
      minSpanY: map['minSpanY'] as int? ?? 1,
      spanX: map['spanX'] as int? ?? 2,
      spanY: map['spanY'] as int? ?? 1,
      maxSpanX: map['maxSpanX'] as int? ?? 5,
      maxSpanY: map['maxSpanY'] as int? ?? 6,
      appIcon: appIcon is Uint8List ? appIcon : null,
      previewImage: preview is Uint8List ? preview : null,
      previewIsGenerated: map['previewIsGenerated'] as bool? ?? false,
    );
  }
}
