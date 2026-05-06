import 'item_info.dart';

class LauncherWidgetInfo extends ItemInfo {
  int appWidgetId;
  String providerPackage;
  String providerClass;
  int minWidth;
  int minHeight;
  int minResizeWidth;
  int minResizeHeight;
  bool isCustomWidget;

  LauncherWidgetInfo({
    required super.id,
    required this.appWidgetId,
    required this.providerPackage,
    required this.providerClass,
    this.minWidth = 0,
    this.minHeight = 0,
    this.minResizeWidth = 0,
    this.minResizeHeight = 0,
    this.isCustomWidget = false,
    super.screenId,
    super.cellX,
    super.cellY,
    super.spanX,
    super.spanY,
    super.container,
  }) : super(itemType: ItemType.appWidget);

  LauncherWidgetInfo copyWith({
    int? appWidgetId,
    String? providerPackage,
    String? providerClass,
    int? minWidth,
    int? minHeight,
    int? minResizeWidth,
    int? minResizeHeight,
    bool? isCustomWidget,
    int? spanX,
    int? spanY,
  }) {
    return LauncherWidgetInfo(
      id: id,
      appWidgetId: appWidgetId ?? this.appWidgetId,
      providerPackage: providerPackage ?? this.providerPackage,
      providerClass: providerClass ?? this.providerClass,
      minWidth: minWidth ?? this.minWidth,
      minHeight: minHeight ?? this.minHeight,
      minResizeWidth: minResizeWidth ?? this.minResizeWidth,
      minResizeHeight: minResizeHeight ?? this.minResizeHeight,
      isCustomWidget: isCustomWidget ?? this.isCustomWidget,
      screenId: screenId,
      cellX: cellX,
      cellY: cellY,
      spanX: spanX ?? this.spanX,
      spanY: spanY ?? this.spanY,
      container: container,
    );
  }
}
