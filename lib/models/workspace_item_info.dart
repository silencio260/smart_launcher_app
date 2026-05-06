import 'dart:typed_data';
import 'item_info.dart';

class WorkspaceItemInfo extends ItemInfo {
  String packageName;
  String? intentAction;
  Uint8List? icon;
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
    this.isDisabled = false,
    this.disabledMessage,
    this.isSystemApp = false,
    this.personKeys = const [],
  });
}
