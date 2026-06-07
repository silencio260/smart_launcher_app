import 'item_info.dart';
import 'workspace_item_info.dart';

enum LabelState { empty, suggested, custom }

class FolderInfo extends ItemInfo {
  String folderTitle;
  List<WorkspaceItemInfo> contents;
  int maxCount;
  String? hint;
  bool isPrivateSecure;
  LabelState labelState;

  FolderInfo({
    required super.id,
    this.folderTitle = '',
    this.contents = const [],
    this.maxCount = 16,
    this.hint,
    this.isPrivateSecure = false,
    this.labelState = LabelState.empty,
    super.container,
    super.screenId,
    super.cellX,
    super.cellY,
    super.user,
    super.rank,
  }) : super(itemType: ItemType.folder, title: folderTitle);
}
