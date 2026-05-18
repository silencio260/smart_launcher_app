import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../state/apps_cubit.dart';

// Subscribes one widget to a single package's badge count without going
// through the AppsCubit Bloc stream. Used by every tile that renders a
// notification dot so badge updates only rebuild the affected leaf.
class BadgeListener extends StatelessWidget {
  final String packageName;
  final Widget Function(BuildContext context, int badge) builder;

  const BadgeListener({
    super.key,
    required this.packageName,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppsCubit>().badges;
    return ValueListenableBuilder<int>(
      valueListenable: store.listenable(packageName),
      builder: (context, badge, _) => builder(context, badge),
    );
  }
}
