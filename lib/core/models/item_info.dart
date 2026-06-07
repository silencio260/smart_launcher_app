enum ItemType { application, deepShortcut, folder, appWidget, appPair }

enum ItemContainer { desktop, hotseat, allApps, folder, hotseatPrediction }

class ItemInfo {
  int id;
  ItemType itemType;
  ItemContainer container;
  int screenId;
  int cellX;
  int cellY;
  int spanX;
  int spanY;
  String user;
  String? componentName;
  String? title;
  int rank;

  ItemInfo({
    required this.id,
    required this.itemType,
    this.container = ItemContainer.desktop,
    this.screenId = 0,
    this.cellX = 0,
    this.cellY = 0,
    this.spanX = 1,
    this.spanY = 1,
    this.user = '',
    this.componentName,
    this.title,
    this.rank = 0,
  });
}
