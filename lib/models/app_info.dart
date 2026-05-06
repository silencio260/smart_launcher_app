import 'dart:typed_data';
import 'item_info.dart';

class AppInfo extends ItemInfo {
  String packageName;
  String appComponentName;
  String userId;
  bool isDisabled;
  bool isHidden;
  Uint8List? icon;

  AppInfo({
    required super.id,
    required this.packageName,
    required this.appComponentName,
    this.userId = '',
    this.isDisabled = false,
    this.isHidden = false,
    this.icon,
    super.title,
    super.rank,
    super.user,
  }) : super(itemType: ItemType.application, componentName: appComponentName);

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      id: 0,
      packageName: map['packageName'] as String,
      appComponentName: map['componentName'] as String? ?? map['packageName'] as String,
      title: map['name'] as String? ?? map['packageName'] as String,
      icon: map['icon'] != null
          ? Uint8List.fromList(List<int>.from(map['icon'] as List))
          : null,
    );
  }

  String get name => title ?? packageName;
}
