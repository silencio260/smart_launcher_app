import 'package:flutter/widgets.dart';

/// Marks a subtree as "in edit mode". Widget-host views inside the workspace
/// read this to drop their `AndroidView`s while edit mode is active, freeing
/// the `appWidgetId` slot so the edit overlay can mount its own live host
/// views for the same widgets.
class EditModeScope extends InheritedWidget {
  final bool active;

  const EditModeScope({
    super.key,
    required this.active,
    required super.child,
  });

  static bool isActive(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<EditModeScope>();
    return scope?.active ?? false;
  }

  @override
  bool updateShouldNotify(EditModeScope oldWidget) =>
      active != oldWidget.active;
}
