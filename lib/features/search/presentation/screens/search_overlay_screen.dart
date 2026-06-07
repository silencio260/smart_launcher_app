import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_launcher_app/features/search/domain/entities/search_result.dart';
import 'package:smart_launcher_app/core/models/launcher_feature.dart';
import 'package:smart_launcher_app/core/platform/feature_launch_dispatcher.dart';
import 'package:smart_launcher_app/features/search/data/app_search_service.dart';
import 'package:smart_launcher_app/features/search/data/calculator_service.dart';
import 'package:smart_launcher_app/features/apps/presentation/bloc/apps_cubit.dart';
import 'package:smart_launcher_app/features/search/presentation/bloc/search_cubit.dart';
import 'package:smart_launcher_app/features/settings/presentation/bloc/settings_cubit.dart';
import 'package:smart_launcher_app/core/widgets/icons/shaped_icon.dart';
import 'package:smart_launcher_app/core/widgets/icons/feature_icon.dart';

class SearchOverlayScreen extends StatefulWidget {
  final String iconShape;

  const SearchOverlayScreen({super.key, this.iconShape = 'squircle'});

  @override
  State<SearchOverlayScreen> createState() => _SearchOverlayScreenState();
}

class _SearchOverlayScreenState extends State<SearchOverlayScreen> {
  final _appSearch = AppSearchService();
  final _calcSearch = CalculatorService();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Don't auto-focus: the keyboard should only appear once the user taps the
    // search field.
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(BuildContext context, String query) {
    context.read<SearchCubit>().setQuery(query);

    if (query.isEmpty) {
      context.read<SearchCubit>().setResults([]);
      return;
    }

    final apps = context.read<AppsCubit>().state.apps;
    final hidden = context.read<SettingsCubit>().state.hiddenApps.toSet();
    final results = <SearchResult>[
      ..._appSearch.search(apps, query, hiddenPackages: hidden),
    ];

    final calc = _calcSearch.evaluate(query);
    if (calc != null) results.insert(0, calc);

    results.add(SearchResult(
      type: SearchResultType.webSearch,
      title: 'Search "$query" on the web',
      score: -1,
    ));

    context.read<SearchCubit>().setResults(results);
  }

  void _onResultTap(BuildContext context, SearchResult result) {
    Navigator.pop(context);
    switch (result.type) {
      case SearchResultType.app:
        if (result.componentName != null) {
          FeatureLaunchDispatcher.launchKey(context, result.componentName!);
        } else if (result.packageName != null) {
          FeatureLaunchDispatcher.launchPackage(context, result.packageName!);
        }
      case SearchResultType.calculator:
        break;
      case SearchResultType.webSearch:
        final q = context.read<SearchCubit>().state.query;
        final intent = Uri.parse(
            'https://www.google.com/search?q=${Uri.encodeComponent(q)}');
        SystemChannels.platform.invokeMethod<void>('SystemNavigator.pop');
        // Launch via platform
        const MethodChannel('com.genrevibes.smartlauncher/system')
            .invokeMethod('launchUrl', {'url': intent.toString()});
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.85),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Search apps, contacts, web…',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white54),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (q) => _onQueryChanged(context, q),
              ),
            ),
            Expanded(
              child: BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) {
                  if (state.results.isEmpty) return const SizedBox.shrink();
                  return ListView.builder(
                    itemCount: state.results.length,
                    itemBuilder: (context, i) {
                      final r = state.results[i];
                      return ListTile(
                        leading: _buildLeading(r),
                        title: Text(r.title,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: r.subtitle != null
                            ? Text(r.subtitle!,
                                style: const TextStyle(color: Colors.white54))
                            : null,
                        onTap: () => _onResultTap(context, r),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        featureId: featureId,
        componentName: r.componentName,
        size: 40,
      );
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
      SearchResultType.contact => Icons.person_outline,
      SearchResultType.file => Icons.insert_drive_file_outlined,
      _ => Icons.search,
    };
    return Icon(icon, color: Colors.white54, size: 32);
  }
}
