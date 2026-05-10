import 'dart:typed_data';

class WidgetProviderInfo {
  final String packageName;
  final String appName;
  final String providerClass;
  final String label;
  final int minWidth;
  final int minHeight;
  final Uint8List? previewImage;

  const WidgetProviderInfo({
    required this.packageName,
    required this.appName,
    required this.providerClass,
    required this.label,
    this.minWidth = 0,
    this.minHeight = 0,
    this.previewImage,
  });

  static WidgetProviderInfo fromMap(Map map) {
    final preview = map['previewImage'];
    return WidgetProviderInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      providerClass: map['providerClass'] as String? ?? '',
      label: map['label'] as String? ?? '',
      minWidth: map['minWidth'] as int? ?? 0,
      minHeight: map['minHeight'] as int? ?? 0,
      previewImage: preview is Uint8List ? preview : null,
    );
  }
}
