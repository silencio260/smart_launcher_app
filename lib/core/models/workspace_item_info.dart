import 'dart:typed_data';
import 'package:smart_launcher_app/core/models/item_info.dart';

class WorkspaceItemInfo extends ItemInfo {
  String packageName;
  String? intentAction;
  Uint8List? icon;
  String? iconPath;
  String? launcherFeatureId;
  bool isDisabled;
  String? disabledMessage;
  bool isSystemApp;
  List<String> personKeys;

  WorkspaceItemInfo({
    required super.id,
    required super.itemType,
    required this.packageName,
    super.container,
    super.screenId,
    super.cellX,
    super.cellY,
    super.spanX,
    super.spanY,
    super.user,
    super.componentName,
    super.title,
    super.rank,
    this.intentAction,
    this.icon,
    this.iconPath,
    this.launcherFeatureId,
    this.isDisabled = false,
    this.disabledMessage,
    this.isSystemApp = false,
    this.personKeys = const [],
  });

  String get launcherKey =>
      launcherFeatureId == null ? packageName : (componentName ?? packageName);
}
