import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/launcher_widget_info.dart';
import '../../models/widget_provider_info.dart';
import '../../services/launcher_service.dart';
import '../../state/settings_cubit.dart';
import '../../state/workspace_cubit.dart';

class WidgetPickerScreen extends StatefulWidget {
  /// Called after a widget is activated and placed on the home screen.
  final void Function(LauncherWidgetInfo widget, int page)? onWidgetAdded;

  const WidgetPickerScreen({super.key, this.onWidgetAdded});

  @override
  State<WidgetPickerScreen> createState() => _WidgetPickerScreenState();
}

class _WidgetPickerScreenState extends State<WidgetPickerScreen> {
  List<WidgetProviderInfo> _providers = [];
  bool _loading = true;
  String _error = '';

  // Which app package names are expanded
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _loadWidgets();
  }

  Future<void> _loadWidgets() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final list = await LauncherService.getAvailableWidgets();
      if (mounted) {
        setState(() {
          _providers = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load widgets: $e';
          _loading = false;
        });
      }
    }
  }

  // Group providers by packageName
  Map<String, List<WidgetProviderInfo>> get _grouped {
    final map = <String, List<WidgetProviderInfo>>{};
    for (final p in _providers) {
      map.putIfAbsent(p.packageName, () => []).add(p);
    }
    return map;
  }

  Future<void> _activateWidget(WidgetProviderInfo provider) async {
    final appWidgetId =
        await LauncherService.bindWidget(provider.packageName, provider.providerClass);
    if (!mounted) return;
    if (appWidgetId < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add widget. Check app permissions.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final workspace = context.read<WorkspaceCubit>();
    final settings = context.read<SettingsCubit>().state;
    final slotsPerPage = settings.gridColumns * settings.gridRows;
    final workspaceState = workspace.state;

    int targetPage = -1;
    int targetSlot = -1;

    for (int p = 0; p < workspaceState.pages.length; p++) {
      for (int s = 0; s < slotsPerPage; s++) {
        final slot = workspaceState.pages[p].slots[s];
        if (slot == null || slot is EmptySlot) {
          targetPage = p;
          targetSlot = s;
          break;
        }
      }
      if (targetPage >= 0) break;
    }

    if (targetPage < 0) {
      workspace.addPage();
      targetPage = workspaceState.pages.length;
      targetSlot = 0;
    }

    final info = LauncherWidgetInfo(
      id: appWidgetId,
      appWidgetId: appWidgetId,
      providerPackage: provider.packageName,
      providerClass: provider.providerClass,
      minWidth: provider.minWidth,
      minHeight: provider.minHeight,
      spanX: 2,
      spanY: 1,
    );

    workspace.addWidget(info, targetPage, targetSlot);
    widget.onWidgetAdded?.call(info, targetPage);

    if (!mounted) return;
    // Pop settings stack back to home
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Widgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadWidgets,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadWidgets, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_providers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.widgets_outlined, size: 64, color: Colors.white30),
            SizedBox(height: 12),
            Text('No widgets found', style: TextStyle(color: Colors.white54)),
          ],
        ),
      );
    }

    final grouped = _grouped;
    final packages = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: packages.length,
      itemBuilder: (context, i) {
        final pkg = packages[i];
        final providers = grouped[pkg]!;
        final isExpanded = _expanded.contains(pkg);
        final appName = providers.first.appName.isNotEmpty
            ? providers.first.appName
            : pkg.split('.').last;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App header row
            ListTile(
              leading: const Icon(Icons.apps, size: 36),
              title: Text(
                appName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${providers.length} widget${providers.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              trailing: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white54,
              ),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expanded.remove(pkg);
                  } else {
                    _expanded.add(pkg);
                  }
                });
              },
            ),
            // Expanded widget list
            if (isExpanded)
              ...providers.map((p) => _WidgetTile(
                    provider: p,
                    onActivate: () => _activateWidget(p),
                  )),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        );
      },
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final WidgetProviderInfo provider;
  final VoidCallback onActivate;

  const _WidgetTile({required this.provider, required this.onActivate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Card(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Preview or placeholder
              Container(
                width: 72,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: provider.previewImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(provider.previewImage!,
                            fit: BoxFit.cover),
                      )
                    : const Center(
                        child: Icon(Icons.widgets_outlined,
                            color: Colors.white38, size: 28),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label.isNotEmpty ? provider.label : 'Widget',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    if (provider.minWidth > 0 || provider.minHeight > 0)
                      Text(
                        '${provider.minWidth}×${provider.minHeight} dp',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38),
                      ),
                  ],
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onActivate,
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
