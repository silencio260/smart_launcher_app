import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/core/models/app_info.dart';
import 'package:smart_launcher_app/core/models/launcher_widget_info.dart';
import 'package:smart_launcher_app/core/models/widget_provider_info.dart';
import 'package:smart_launcher_app/core/platform/launcher_service.dart';
import 'package:smart_launcher_app/core/services/widget_provider_cache_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/features/home/presentation/bloc/workspace_cubit.dart';
import 'package:smart_launcher_app/core/utils/debug_flags.dart';
import 'package:smart_launcher_app/core/widgets/icons/feature_icon.dart';
import 'package:smart_launcher_app/core/widgets/icons/shaped_icon.dart';
import 'package:smart_launcher_app/features/home/presentation/widgets/workspace/widget_grid_math.dart';

class WidgetPickerScreen extends StatefulWidget {
  /// Called after a widget is activated and placed on the home screen.
  final void Function(LauncherWidgetInfo widget, int page)? onWidgetAdded;

  /// When set, the picker forwards the activated widget here INSTEAD of placing
  /// it on the first available slot. Used by "Create stack" / "Edit stack" to
  /// merge the picked widget into an existing slot.
  final void Function(LauncherWidgetInfo widget)? onWidgetPicked;

  /// Test seam: override the cache service. Production uses the singleton.
  final WidgetProviderCacheService? cacheService;

  /// Test seam: override the platform fetch. Production calls
  /// [LauncherService.getAvailableWidgets].
  final Future<List<WidgetProviderInfo>> Function({
    required int gridColumns,
    required int gridRows,
    required double cellWidth,
    required double cellHeight,
    required double gap,
  })? fetchWidgets;

  const WidgetPickerScreen({
    super.key,
    this.onWidgetAdded,
    this.onWidgetPicked,
    this.cacheService,
    this.fetchWidgets,
  });

  @override
  State<WidgetPickerScreen> createState() => _WidgetPickerScreenState();
}

const _androidLauncherPackage =
    'com.smartphonelauncherapp.smart.phone.device.launcher.smart_launcher_app';

class _WidgetPickerScreenState extends State<WidgetPickerScreen> {
  List<WidgetProviderInfo> _providers = [];
  bool _loading = true;
  bool _refreshing = false;
  String _error = '';
  bool _loadedInitialWidgets = false;
  bool _requestedLauncherApps = false;
  bool _requestedLauncherPackageIcon = false;
  Uint8List? _launcherPackageIcon;

  // Which app package names are expanded
  final Set<String> _expanded = {};

  WidgetProviderCacheService get _cache =>
      widget.cacheService ?? WidgetProviderCacheService.instance;

  Future<List<WidgetProviderInfo>> _fetch({
    required int gridColumns,
    required int gridRows,
    required double cellWidth,
    required double cellHeight,
    required double gap,
  }) async {
    final override = widget.fetchWidgets;
    final providers = override != null
        ? await override(
            gridColumns: gridColumns,
            gridRows: gridRows,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            gap: gap,
          )
        : await LauncherService.getAvailableWidgets(
            gridColumns: gridColumns,
            gridRows: gridRows,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            gap: gap,
          );
    return _visiblePlatformWidgets(providers);
  }

  List<WidgetProviderInfo> _visiblePlatformWidgets(
    List<WidgetProviderInfo> providers,
  ) {
    return providers
        .where((provider) => provider.packageName != _androidLauncherPackage)
        .toList(growable: false);
  }

  Uint8List? _preferredLauncherIconForPackage(
    String packageName,
    List<AppInfo> apps,
  ) {
    Uint8List? fallback;
    for (final app in apps) {
      if (app.packageName != packageName) continue;
      final icon = app.icon;
      if (icon == null || icon.isEmpty) continue;
      if (!app.isInternalFeature) return icon;
      fallback ??= icon;
    }
    return fallback;
  }

  Uint8List? _realLauncherAppIcon(List<AppInfo> apps) {
    final packageIcon = _launcherPackageIcon;
    if (packageIcon != null && packageIcon.isNotEmpty) return packageIcon;
    for (final app in apps) {
      if (app.packageName != _androidLauncherPackage || app.isInternalFeature) {
        continue;
      }
      final icon = app.icon;
      if (icon != null && icon.isNotEmpty) return icon;
    }
    return null;
  }

  Uint8List? _iconForPackage(
    String packageName,
    List<AppInfo> apps,
    List<WidgetProviderInfo> providers,
  ) {
    if (packageName == WorkspaceCubit.defaultClockProviderPackage) {
      return _realLauncherAppIcon(apps);
    }
    return _preferredLauncherIconForPackage(packageName, apps) ??
        _firstProviderIcon(providers);
  }

  Uint8List? _firstProviderIcon(List<WidgetProviderInfo> providers) {
    for (final provider in providers) {
      final icon = provider.appIcon;
      if (icon != null && icon.isNotEmpty) return icon;
    }
    return null;
  }

  String _appNameForPackage(
    String packageName,
    WidgetProviderInfo fallbackProvider,
  ) {
    if (packageName == WorkspaceCubit.defaultClockProviderPackage) {
      return 'Smart Launcher';
    }
    return fallbackProvider.appName.isNotEmpty
        ? fallbackProvider.appName
        : packageName.split('.').last;
  }

  String? _featureIconForPackage(String packageName) => null;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureLauncherAppsLoaded();
    _ensureLauncherPackageIconLoaded();
    if (_loadedInitialWidgets) return;
    _loadedInitialWidgets = true;
    _bootstrap();
  }

  void _ensureLauncherAppsLoaded() {
    if (_requestedLauncherApps) return;
    final appsCubit = context.read<AppsCubit>();
    if (appsCubit.state.apps.isNotEmpty || appsCubit.state.loading) return;
    _requestedLauncherApps = true;
    unawaited(appsCubit.loadCachedThenRefresh());
  }

  void _ensureLauncherPackageIconLoaded() {
    if (_requestedLauncherPackageIcon) return;
    _requestedLauncherPackageIcon = true;
    unawaited(_loadLauncherPackageIcon());
  }

  Future<void> _loadLauncherPackageIcon() async {
    try {
      final icon =
          await LauncherService.getPackageIcon(_androidLauncherPackage);
      if (!mounted || icon == null || icon.isEmpty) return;
      setState(() {
        _launcherPackageIcon = icon;
      });
    } catch (_) {
      // Do not fall back to feature aliases here: this package also owns
      // mini-app aliases, which can make the Smart Launcher widget show Notes.
    }
  }

  ({double cellWidth, double cellHeight, int gridColumns, int gridRows})
      _computeGrid() {
    final settings = context.read<SettingsCubit>().state;
    final mediaQuery = MediaQuery.of(context);
    const gap = 8.0;
    final cellWidth =
        (mediaQuery.size.width - 16.0 - (settings.gridColumns - 1) * gap) /
            settings.gridColumns;
    final hotseatSlotHeight = settings.iconSize +
        (settings.showDockLabels ? settings.iconSize * 0.6 : 16.0);
    final hotseatTotalHeight = settings.showDock
        ? hotseatSlotHeight + 24.0 + mediaQuery.padding.bottom + 12.0
        : 0.0;
    final workspaceHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        8.0 -
        hotseatTotalHeight -
        16.0;
    final cellHeight =
        (workspaceHeight - (settings.gridRows - 1) * gap) / settings.gridRows;
    return (
      cellWidth: cellWidth,
      cellHeight: cellHeight,
      gridColumns: settings.gridColumns,
      gridRows: settings.gridRows,
    );
  }

  Future<void> _bootstrap() async {
    final grid = _computeGrid();
    final key = WidgetCacheKey.from(
      gridColumns: grid.gridColumns,
      gridRows: grid.gridRows,
      cellWidth: grid.cellWidth,
      cellHeight: grid.cellHeight,
    );

    final cached = await _cache.load(key);
    final visibleCached =
        cached == null ? null : _visiblePlatformWidgets(cached);
    if (!mounted) return;
    if (visibleCached != null && visibleCached.isNotEmpty) {
      setState(() {
        _providers = [_builtinClockProvider(), ...visibleCached];
        _loading = false;
        _refreshing = true;
        _error = '';
      });
    }
    await _refreshFromPlatform(key);
  }

  Future<void> _refreshFromPlatform(WidgetCacheKey key) async {
    final grid = _computeGrid();
    if (mounted) {
      setState(() {
        _refreshing = true;
        if (_providers.isEmpty) _loading = true;
      });
    }
    widgetLog(
      '[WidgetPickerSizing] refresh '
      'grid=${grid.gridColumns}x${grid.gridRows} '
      'cell=${grid.cellWidth.toStringAsFixed(2)}x${grid.cellHeight.toStringAsFixed(2)}',
    );
    try {
      final list = await _fetch(
        gridColumns: grid.gridColumns,
        gridRows: grid.gridRows,
        cellWidth: grid.cellWidth,
        cellHeight: grid.cellHeight,
        gap: 8.0,
      );
      if (!mounted) return;
      setState(() {
        _providers = [_builtinClockProvider(), ...list];
        _loading = false;
        _refreshing = false;
        _error = '';
      });
      // Cache only the platform-derived providers, never the synthetic
      // builtin clock — that's re-prepended on every load.
      unawaited(_cache.save(key, list));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        if (_providers.isEmpty) {
          _error = 'Could not load widgets: $e';
          _loading = false;
        }
      });
      if (_providers.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh widgets. Showing cached list.'),
          ),
        );
      }
    }
  }

  Future<void> _onPullToRefresh() async {
    final grid = _computeGrid();
    final key = WidgetCacheKey.from(
      gridColumns: grid.gridColumns,
      gridRows: grid.gridRows,
      cellWidth: grid.cellWidth,
      cellHeight: grid.cellHeight,
    );
    await _refreshFromPlatform(key);
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
    if (_isBuiltinClock(provider)) {
      await _activateBuiltinClock();
      return;
    }
    final appWidgetId = await LauncherService.bindWidget(
        provider.packageName, provider.providerClass);
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
    final initialSpan = _initialSpanForProvider(provider);
    widgetLog(
      '[WidgetPickerSizing] activate provider=${provider.packageName}/${provider.providerClass} '
      'label="${provider.label}" '
      'appWidgetId=$appWidgetId grid=${settings.gridColumns}x${settings.gridRows} '
      'rawMin=${provider.minWidth}x${provider.minHeight} '
      'rawMinResize=${provider.minResizeWidth}x${provider.minResizeHeight} '
      'rawMaxResize=${provider.maxResizeWidth}x${provider.maxResizeHeight} '
      'target=${provider.targetCellWidth}x${provider.targetCellHeight} '
      'resizeMode=${provider.resizeMode} '
      'providerSpan=${provider.spanX}x${provider.spanY} '
      'providerMinSpan=${provider.minSpanX}x${provider.minSpanY} '
      'providerMaxSpan=${provider.maxSpanX}x${provider.maxSpanY} '
      'chosenInitialSpan=${initialSpan.$1}x${initialSpan.$2}',
    );

    final info = LauncherWidgetInfo(
      id: appWidgetId,
      appWidgetId: appWidgetId,
      providerPackage: provider.packageName,
      providerClass: provider.providerClass,
      minWidth: provider.minWidth,
      minHeight: provider.minHeight,
      minResizeWidth: provider.minResizeWidth,
      minResizeHeight: provider.minResizeHeight,
      maxResizeWidth: provider.maxResizeWidth,
      maxResizeHeight: provider.maxResizeHeight,
      resizeMode: provider.resizeMode,
      minSpanX: provider.minSpanX,
      minSpanY: provider.minSpanY,
      maxSpanX: provider.maxSpanX,
      maxSpanY: provider.maxSpanY,
      spanX: initialSpan.$1,
      spanY: initialSpan.$2,
    );

    // Stack-target flow: skip first-available placement and hand the widget
    // back to the caller so it can merge into an existing widget slot.
    if (widget.onWidgetPicked != null) {
      widget.onWidgetPicked!.call(info);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final placement = workspace.addWidgetToFirstAvailableSlot(
      info,
      settings.gridColumns,
      settings.gridRows,
    );
    widgetLog(
      '[WidgetPickerSizing] placed provider=${provider.packageName}/${provider.providerClass} '
      'page=${placement.page} slot=${placement.slot} '
      'storedSpan=${info.spanX}x${info.spanY}',
    );
    widget.onWidgetAdded?.call(info, placement.page);

    if (!mounted) return;
    // Pop settings stack back to home
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  bool _isBuiltinClock(WidgetProviderInfo provider) =>
      _isBuiltinClockProvider(provider);

  WidgetProviderInfo _builtinClockProvider() => const WidgetProviderInfo(
        packageName: WorkspaceCubit.defaultClockProviderPackage,
        appName: 'Smart Launcher',
        providerClass: WorkspaceCubit.defaultClockProviderClass,
        label: 'Clock',
        minSpanX: WorkspaceCubit.defaultClockMinSpanX,
        minSpanY: WorkspaceCubit.defaultClockMinSpanY,
        spanX: WorkspaceCubit.defaultClockMaxSpanX,
        spanY: WorkspaceCubit.defaultClockMaxSpanY,
        maxSpanX: WorkspaceCubit.defaultClockMaxSpanX,
        maxSpanY: WorkspaceCubit.defaultClockMaxSpanY,
        resizeMode: 3,
      );

  Future<void> _activateBuiltinClock() async {
    final workspace = context.read<WorkspaceCubit>();
    final settings = context.read<SettingsCubit>().state;

    if (widget.onWidgetPicked != null) {
      final info = workspace.defaultClockWidgetForSelection(
        settings.gridColumns,
        settings.gridRows,
      );
      widget.onWidgetPicked!.call(info);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    final placement = workspace.addDefaultClockWidgetToFirstAvailableSlot(
      settings.gridColumns,
      settings.gridRows,
    );
    widget.onWidgetAdded?.call(placement.widget, placement.page);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  (int, int) _initialSpanForProvider(WidgetProviderInfo provider) {
    final grid = _computeGrid();
    return _preferredCellsForProvider(
      provider,
      gridColumns: grid.gridColumns,
      gridRows: grid.gridRows,
      cellWidth: grid.cellWidth,
      cellHeight: grid.cellHeight,
    );
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
            onPressed: _refreshing ? null : _onPullToRefresh,
          ),
        ],
        bottom: _refreshing && !_loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final apps = context.watch<AppsCubit>().state.apps;
    final settings = context.watch<SettingsCubit>().state;
    final mediaQuery = MediaQuery.of(context);
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
            FilledButton(
              onPressed: _onPullToRefresh,
              child: const Text('Retry'),
            ),
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
    final packages = grouped.keys.toList()
      ..sort((a, b) {
        final nameA = (grouped[a]!.first.appName.isNotEmpty
                ? grouped[a]!.first.appName
                : a.split('.').last)
            .toLowerCase();
        final nameB = (grouped[b]!.first.appName.isNotEmpty
                ? grouped[b]!.first.appName
                : b.split('.').last)
            .toLowerCase();
        return nameA.compareTo(nameB);
      });

    return RefreshIndicator(
      onRefresh: _onPullToRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: packages.length,
        itemBuilder: (context, i) {
          final pkg = packages[i];
          final providers = grouped[pkg]!
            ..sort((a, b) =>
                a.label.toLowerCase().compareTo(b.label.toLowerCase()));
          final isExpanded = _expanded.contains(pkg);
          final appIcon = _iconForPackage(pkg, apps, providers);
          final appName = _appNameForPackage(pkg, providers.first);
          final featureIconId = _featureIconForPackage(pkg);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App header row
              ListTile(
                leading: _WidgetAppIcon(
                  iconBytes: appIcon,
                  featureId: featureIconId,
                  shape: settings.iconShape,
                ),
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
                      appIcon: appIcon,
                      featureIconId: featureIconId,
                      iconShape: settings.iconShape,
                      gridColumns: settings.gridColumns,
                      gridRows: settings.gridRows,
                      cellWidth: (mediaQuery.size.width -
                              16.0 -
                              (settings.gridColumns - 1) * 8.0) /
                          settings.gridColumns,
                      cellHeight: ((mediaQuery.size.height -
                                  mediaQuery.padding.top -
                                  8.0 -
                                  (settings.showDock
                                      ? (settings.iconSize +
                                          (settings.showDockLabels
                                              ? settings.iconSize * 0.6
                                              : 16.0) +
                                          24.0 +
                                          mediaQuery.padding.bottom +
                                          12.0)
                                      : 0.0) -
                                  16.0) -
                              (settings.gridRows - 1) * 8.0) /
                          settings.gridRows,
                      showDebugOverlay: settings.showWidgetPickerDebugInfo,
                      onActivate: () => _activateWidget(p),
                    )),
              const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          );
        },
      ),
    );
  }
}

bool _isBuiltinClockProvider(WidgetProviderInfo provider) =>
    provider.packageName == WorkspaceCubit.defaultClockProviderPackage &&
    provider.providerClass == WorkspaceCubit.defaultClockProviderClass;

class _BuiltinClockPreview extends StatelessWidget {
  const _BuiltinClockPreview();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$hour:$minute',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 0,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 7),
                      child: Text(
                        suffix,
                        style: const TextStyle(
                          color: Color(0xFFB8B8BE),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${days[now.weekday - 1]}  ${months[now.month - 1]} ${now.day}',
                  style: const TextStyle(
                    color: Color(0xFFB8B8BE),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final WidgetProviderInfo provider;
  final Uint8List? appIcon;
  final String? featureIconId;
  final String iconShape;
  final int gridColumns;
  final int gridRows;
  final double cellWidth;
  final double cellHeight;
  final bool showDebugOverlay;
  final VoidCallback onActivate;

  const _WidgetTile({
    required this.provider,
    required this.appIcon,
    this.featureIconId,
    required this.iconShape,
    required this.gridColumns,
    required this.gridRows,
    required this.cellWidth,
    required this.cellHeight,
    required this.showDebugOverlay,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    final (minCellsX, minCellsY) = _preferredCellsForProvider(
      provider,
      gridColumns: gridColumns,
      gridRows: gridRows,
      cellWidth: cellWidth,
      cellHeight: cellHeight,
    );

    final isBuiltinClock = _isBuiltinClockProvider(provider);
    final useExpandedPreview = isBuiltinClock ||
        (provider.previewIsGenerated && provider.previewImage != null);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Card(
        color: Colors.white.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            useExpandedPreview
                ? _buildExpandedPreview(
                    minCellsX,
                    minCellsY,
                    isBuiltinClock,
                  )
                : _buildCompactRow(minCellsX, minCellsY),
            if (showDebugOverlay) _buildDebugInfo(minCellsX, minCellsY),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedPreview(
    int minCellsX,
    int minCellsY,
    bool isBuiltinClock,
  ) {
    final aspectRatio = (minCellsX / minCellsY).clamp(0.5, 4.0);
    final previewHeight = (220.0 * minCellsY / minCellsX).clamp(140.0, 280.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: previewHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: isBuiltinClock
                      ? const _BuiltinClockPreview()
                      : Image.memory(
                          provider.previewImage!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _WidgetAppIcon(
                iconBytes: appIcon,
                featureId: featureIconId,
                shape: iconShape,
                size: 32,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label.isNotEmpty ? provider.label : 'Widget',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    Text(
                      '$minCellsX x $minCellsY cells',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white38),
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
      ],
    );
  }

  Widget _buildCompactRow(int minCellsX, int minCellsY) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
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
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          provider.previewImage!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: _WidgetAppIcon(
                            iconBytes: appIcon,
                            featureId: featureIconId,
                            shape: iconShape,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      const Center(
                        child: Icon(Icons.widgets_outlined,
                            color: Colors.white38, size: 28),
                      ),
                      Positioned(
                        right: 4,
                        bottom: 4,
                        child: _WidgetAppIcon(
                          iconBytes: appIcon,
                          featureId: featureIconId,
                          shape: iconShape,
                          size: 16,
                        ),
                      ),
                    ],
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
                Text(
                  '$minCellsX x $minCellsY cells',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
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
    );
  }

  Widget _buildDebugInfo(int spanX, int spanY) {
    final gap = 8.0;
    final defaultW = spanX * cellWidth + (spanX - 1) * gap;
    final defaultH = spanY * cellHeight + (spanY - 1) * gap;

    final minSpanX = provider.minSpanX.clamp(1, gridColumns);
    final minSpanY = provider.minSpanY.clamp(1, gridRows);
    final maxSpanX = provider.maxSpanX.clamp(1, gridColumns);
    final maxSpanY = provider.maxSpanY.clamp(1, gridRows);
    final minW = minSpanX * cellWidth + (minSpanX - 1) * gap;
    final minH = minSpanY * cellHeight + (minSpanY - 1) * gap;
    final maxW = maxSpanX * cellWidth + (maxSpanX - 1) * gap;
    final maxH = maxSpanY * cellHeight + (maxSpanY - 1) * gap;

    const labelStyle =
        TextStyle(fontSize: 10, color: Colors.amber, fontFamily: 'monospace');
    const valueStyle =
        TextStyle(fontSize: 10, color: Colors.white70, fontFamily: 'monospace');

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(label, style: labelStyle),
              ),
              Expanded(child: Text(value, style: valueStyle)),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.55),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('── DEBUG ──',
              style: labelStyle.copyWith(
                  color: Colors.amber.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          row('default span', '${spanX}c × ${spanY}r'),
          row('default dp',
              '${defaultW.toStringAsFixed(1)} × ${defaultH.toStringAsFixed(1)} dp'),
          row('minWidth/Height',
              '${provider.minWidth} × ${provider.minHeight} dp'),
          row('min span', '${minSpanX}c × ${minSpanY}r'),
          row('min dp',
              '${minW.toStringAsFixed(1)} × ${minH.toStringAsFixed(1)} dp'),
          row('max span', '${maxSpanX}c × ${maxSpanY}r'),
          row('max dp',
              '${maxW.toStringAsFixed(1)} × ${maxH.toStringAsFixed(1)} dp'),
          if (provider.targetCellWidth > 0 || provider.targetCellHeight > 0)
            row('targetCell (API31)',
                '${provider.targetCellWidth}c × ${provider.targetCellHeight}r'),
          row('resizeMode', _resizeModeLabel(provider.resizeMode)),
          row('cell size',
              '${cellWidth.toStringAsFixed(1)} × ${cellHeight.toStringAsFixed(1)} dp'),
          row('grid', '${gridColumns}col × ${gridRows}row'),
        ],
      ),
    );
  }

  String _resizeModeLabel(int mode) => switch (mode) {
        0 => 'none',
        1 => 'horizontal',
        2 => 'vertical',
        3 => 'both',
        _ => 'unknown ($mode)',
      };
}

(int, int) _preferredCellsForProvider(
  WidgetProviderInfo provider, {
  required int gridColumns,
  required int gridRows,
  required double cellWidth,
  required double cellHeight,
}) {
  // provider.spanX/Y already accounts for targetCellWidth/Height (clamped to
  // this grid) via WidgetSizing.fromProviderInfo on the native side.
  // Using raw targetCellWidth/Height here would apply the widget's declared
  // cell count against a different (larger) reference grid.
  //
  // The effective span must match what cell_layout will render — otherwise
  // placement reserves a slot smaller than the widget and it bleeds past the
  // grid edge. See effectiveWidgetSpan in widget_grid_math.dart.
  final effective = effectiveWidgetSpan(
    storedSpanX: provider.spanX,
    storedSpanY: provider.spanY,
    minSpanX: provider.minSpanX,
    minSpanY: provider.minSpanY,
    maxSpanX: provider.maxSpanX,
    maxSpanY: provider.maxSpanY,
    minWidth: provider.minWidth,
    minHeight: provider.minHeight,
    minResizeWidth: provider.minResizeWidth,
    minResizeHeight: provider.minResizeHeight,
    maxResizeWidth: provider.maxResizeWidth,
    maxResizeHeight: provider.maxResizeHeight,
    resizeMode: provider.resizeMode,
    gridColumns: gridColumns,
    gridRows: gridRows,
    cellWidth: cellWidth,
    cellHeight: cellHeight,
  );
  final result = (effective.spanX, effective.spanY);
  widgetLog(
    '[WidgetPickerSizing] preferredCells provider=${provider.packageName}/${provider.providerClass} '
    'grid=${gridColumns}x$gridRows '
    'providerSpan=${provider.spanX}x${provider.spanY} '
    'target=${provider.targetCellWidth}x${provider.targetCellHeight} '
    'minSpan=${provider.minSpanX}x${provider.minSpanY} '
    'maxSpan=${provider.maxSpanX}x${provider.maxSpanY} '
    'result=${result.$1}x${result.$2}',
  );
  return result;
}

class _WidgetAppIcon extends StatelessWidget {
  final Uint8List? iconBytes;
  final String? featureId;
  final String shape;
  final double size;

  const _WidgetAppIcon({
    required this.iconBytes,
    this.featureId,
    required this.shape,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: iconBytes != null
          ? ShapedIcon(iconBytes: iconBytes, shape: shape, size: size)
          : featureId != null
              ? FeatureIcon(featureId: featureId, size: size)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(size * 0.28),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Icon(
                    Icons.apps_rounded,
                    size: size * 0.55,
                    color: Colors.white54,
                  ),
                ),
    );
  }
}
