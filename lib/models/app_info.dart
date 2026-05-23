import 'dart:typed_data';
import 'item_info.dart';

class AppInfo extends ItemInfo {
  String packageName;
  String appComponentName;
  String userId;
  bool isDisabled;
  Uint8List? icon;
  String? iconPath;

  AppInfo({
    required super.id,
    required this.packageName,
    required this.appComponentName,
    this.userId = '',
    this.isDisabled = false,
    this.icon,
    this.iconPath,
    super.title,
    super.rank,
    super.user,
  }) : super(itemType: ItemType.application, componentName: appComponentName);

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawIcon = map['icon'];
    return AppInfo(
      id: 0,
      packageName: map['packageName'] as String,
      appComponentName:
          map['componentName'] as String? ?? map['packageName'] as String,
      title: map['name'] as String? ?? map['packageName'] as String,
      icon: rawIcon is Uint8List
          ? rawIcon
          : rawIcon is List
              ? Uint8List.fromList(List<int>.from(rawIcon))
              : null,
      iconPath: map['iconPath'] as String?,
    );
  }

  String get name => title ?? packageName;
}
