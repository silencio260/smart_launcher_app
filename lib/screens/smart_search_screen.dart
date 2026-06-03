import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/app_info.dart';
import '../models/launcher_feature.dart';
import '../models/search_result.dart';
import '../services/feature_launch_dispatcher.dart';
import '../services/search/app_search_service.dart';
import '../services/search/calculator_service.dart';
import '../services/search/recent_searches_store.dart';
import '../state/apps_cubit.dart';
import '../state/settings_cubit.dart';
import '../widgets/icons/shaped_icon.dart';
import '../widgets/icons/feature_icon.dart';

/// A standard Android settings screen surfaced as a chip in Smart search. The
/// [action] is an `android.provider.Settings.ACTION_*` string handled natively.
class _SettingsShortcut {
  final String label;
  final IconData icon;
  final String action;
  const _SettingsShortcut(this.label, this.icon, this.action);
}

const _kSettingsShortcuts = <_SettingsShortcut>[
  _SettingsShortcut('Wi-Fi', Icons.wifi, 'android.settings.WIFI_SETTINGS'),
  _SettingsShortcut(
      'Bluetooth', Icons.bluetooth, 'android.settings.BLUETOOTH_SETTINGS'),
  _SettingsShortcut(
      'Display', Icons.brightness_6, 'android.settings.DISPLAY_SETTINGS'),
  _SettingsShortcut('Apps', Icons.apps,
      'android.settings.APPLICATION_SETTINGS'),
  _SettingsShortcut('Battery', Icons.battery_full,
      'android.settings.BATTERY_SAVER_SETTINGS'),
  _SettingsShortcut(
      'Security', Icons.shield_outlined, 'android.settings.SECURITY_SETTINGS'),
];

/// The richer Smart-search screen opened from the permanent home pill. Searches
/// installed apps, evaluates calculator expressions, offers a web fallback, and
/// — when idle — shows suggested apps, recent searches, and settings shortcuts.
class SmartSearchScreen extends StatefulWidget {
  final String iconShape;

  const SmartSearchScreen({super.key, this.iconShape = 'squircle'});

  @override
  State<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends State<SmartSearchScreen> {
  static const _system = MethodChannel('com.genrevibes.smartlauncher/system');

  final _appSearch = AppSearchService();
  final _calcSearch = CalculatorService();
  final _recentsStore = RecentSearchesStore();
  final _focusNode = FocusNode();
  final _controller = TextEditingController();

  String _query = '';
  List<SearchResult> _results = const [];
  List<String> _recents = const [];

  @override
  void initState() {
    super.initState();
    _recentsStore.load().then((value) {
      if (mounted) setState(() => _recents = value);
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Set<String> get _hidden =>
      context.read<SettingsCubit>().state.hiddenApps.toSet();

  List<AppInfo> get _visibleApps {
    final hidden = _hidden;
    return context
        .read<AppsCubit>()
        .state
        .apps
        .where((a) =>
            !hidden.contains(a.launcherKey) && !hidden.contains(a.packageName))
        .toList();
  }

  void _onQueryChanged(String query) {
    setState(() {
      _query = query;
      if (query.isEmpty) {
        _results = const [];
        return;
      }
      final results = <SearchResult>[
        ..._appSearch.search(_visibleApps, query, hiddenPackages: _hidden),
      ];
      final calc = _calcSearch.evaluate(query);
      if (calc != null) results.insert(0, calc);
      results.add(SearchResult(
        type: SearchResultType.webSearch,
        title: 'Search "$query" on the web',
        score: -1,
      ));
      _results = results;
    });
  }

  Future<void> _rememberQuery(String query) async {
    final updated = await _recentsStore.add(query);
    if (mounted) setState(() => _recents = updated);
  }

  void _launchApp(SearchResult result) {
    _rememberQuery(_query);
    Navigator.pop(context);
    if (result.componentName != null) {
      FeatureLaunchDispatcher.launchKey(context, result.componentName!);
    } else if (result.packageName != null) {
      FeatureLaunchDispatcher.launchPackage(context, result.packageName!);
    }
  }

  void _launchWeb() {
    _rememberQuery(_query);
    Navigator.pop(context);
    final url =
        'https://www.google.com/search?q=${Uri.encodeComponent(_query)}';
    _system.invokeMethod('launchUrl', {'url': url});
  }

  void _onResultTap(SearchResult result) {
    switch (result.type) {
      case SearchResultType.app:
        _launchApp(result);
      case SearchResultType.webSearch:
        _launchWeb();
      case SearchResultType.calculator:
        break;
      default:
        break;
    }
  }

  void _runRecent(String query) {
    _controller.text = query;
    _controller.selection =
        TextSelection.collapsed(offset: query.length);
    _onQueryChanged(query);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.88),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchField(),
            Expanded(
              child: _query.isEmpty ? _buildIdle() : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (_query.trim().isNotEmpty) _launchWeb();
        },
        decoration: InputDecoration(
          hintText: 'Search apps and the web…',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: () => Navigator.pop(context),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: _onQueryChanged,
      ),
    );
  }

  Widget _buildResults() {
    if (_results.isEmpty) return const SizedBox.shrink();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final r = _results[i];
        return ListTile(
          leading: _buildLeading(r),
          title: Text(r.title, style: const TextStyle(color: Colors.white)),
          subtitle: r.subtitle != null
              ? Text(r.subtitle!,
                  style: const TextStyle(color: Colors.white54))
              : null,
          onTap: () => _onResultTap(r),
        );
      },
    );
  }

  Widget _buildIdle() {
    final suggestions = _visibleApps.take(8).toList();
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (suggestions.isNotEmpty) ...[
          _sectionLabel('Suggestions'),
          const SizedBox(height: 8),
          _SuggestionsGrid(
            apps: suggestions,
            onTap: (app) {
              _rememberQuery(app.name);
              Navigator.pop(context);
              FeatureLaunchDispatcher.launch(context, app);
            },
          ),
          const SizedBox(height: 24),
        ],
        if (_recents.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: _sectionLabel('Recent searches')),
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.delete_outline,
                    color: Colors.white54, size: 20),
                onPressed: () async {
                  await _recentsStore.clear();
                  if (mounted) setState(() => _recents = const []);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final q in _recents)
                _Chip(
                  label: q,
                  onTap: () => _runRecent(q),
                  onRemove: () async {
                    final updated = await _recentsStore.remove(q);
                    if (mounted) setState(() => _recents = updated);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
        _sectionLabel('Settings'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _kSettingsShortcuts)
              _Chip(
                label: s.label,
                icon: s.icon,
                onTap: () => _system
                    .invokeMethod('openSettingsAction', {'action': s.action}),
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );

  Widget _buildLeading(SearchResult r) {
    final featureId = LauncherFeatureCatalog.idForComponent(r.componentName);
    if (featureId != null) {
      if (r.icon != null || (r.iconPath?.isNotEmpty ?? false)) {
        return ShapedIcon(
          iconBytes: r.icon,
          iconPath: r.iconPath,
          shape: widget.iconShape,
          size: 40,
          cacheKey: r.componentName ?? r.packageName,
        );
      }
      return FeatureIcon(
          featureId: featureId, componentName: r.componentName, size: 40);
    }
    if (r.icon != null || (r.iconPath?.isNotEmpty ?? false)) {
      return ShapedIcon(
        iconBytes: r.icon,
        iconPath: r.iconPath,
        shape: widget.iconShape,
        size: 40,
        cacheKey: r.packageName,
      );
    }
    final icon = switch (r.type) {
      SearchResultType.calculator => Icons.calculate_outlined,
      SearchResultType.webSearch => Icons.public,
      _ => Icons.search,
    };
    return Icon(icon, color: Colors.white54, size: 32);
  }
}

class _SuggestionsGrid extends StatelessWidget {
  final List<AppInfo> apps;
  final void Function(AppInfo app) onTap;

  const _SuggestionsGrid({required this.apps, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: apps.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final app = apps[i];
        return GestureDetector(
          onTap: () => onTap(app),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AppThumb(app: app),
              const SizedBox(height: 6),
              Text(
                app.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppThumb extends StatelessWidget {
  final AppInfo app;
  const _AppThumb({required this.app});

  @override
  Widget build(BuildContext context) {
    final featureId = app.launcherFeatureId;
    if (featureId != null) {
      return FeatureIcon(
        featureId: featureId,
        componentName: app.appComponentName,
        size: 48,
      );
    }
    return ShapedIcon(
      iconBytes: app.icon,
      iconPath: app.iconPath,
      shape: 'squircle',
      size: 48,
      cacheKey: app.packageName,
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Future<void> Function()? onRemove;

  const _Chip({
    required this.label,
    required this.onTap,
    this.icon,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white70),
                const SizedBox(width: 7),
              ],
              Text(label, style: const TextStyle(color: Colors.white)),
              if (onRemove != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onRemove!.call(),
                  child: const Icon(Icons.close, size: 15, color: Colors.white54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
