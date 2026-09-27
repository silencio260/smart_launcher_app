import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:smart_launcher_app/core/models/wallpaper_item.dart';
import 'package:smart_launcher_app/core/services/wallpaper_api.dart';

/// Screen-owned feed. Metadata stays in memory only until the server expiry.
class WallpaperFeedController extends ChangeNotifier
    with WidgetsBindingObserver {
  WallpaperFeedController() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _api = WallpaperApi();
  final List<WallpaperItem> _items = [];
  final List<dynamic> _notices = [];
  final List<WallpaperCategory> _categories = [];
  final List<WallpaperCategory> _catalogCategories = [];
  Future<void>? _catalogRequest;
  List<WallpaperItem> get items => List.unmodifiable(_items);
  List<dynamic> get notices => List.unmodifiable(_notices);
  List<WallpaperCategory> get categories {
    final byId = <int, WallpaperCategory>{
      for (final category in _categories) category.id: category,
      for (final category in _catalogCategories) category.id: category,
    };
    return List.unmodifiable(byId.values);
  }

  Future<void> loadCategories() => _catalogRequest ??= _loadCategories();

  Future<void> _loadCategories() async {
    try {
      final categories = await _api.fetchCategories();
      if (_disposed) return;
      _catalogCategories
        ..clear()
        ..addAll(categories);
      notifyListeners();
    } on WallpaperApiException {
      // Wallpaper pages remain usable if category discovery is unavailable.
    } finally {
      _catalogRequest = null;
    }
  }

  int? selectedCategoryId;
  String? selectedSearch;
  String? snapshot;
  int? nextPage;
  DateTime? expiresAt;
  String? environment;
  WallpaperApiException? error;
  bool loading = false;
  bool _disposed = false;
  int _generation = 0;
  Timer? _expiryTimer;

  bool get isExpired =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);
  bool get needsReload =>
      snapshot == null ||
      error?.kind == WallpaperFailure.expired ||
      error?.kind == WallpaperFailure.invalidRequest;

  Future<void> refresh() => _load(refresh: true);
  Future<void> loadMore() => needsReload ? refresh() : _load(refresh: false);

  Future<void> selectCategory(int? categoryId) async {
    if (_disposed ||
        loading ||
        (selectedCategoryId == categoryId && selectedSearch == null)) {
      return;
    }
    await _load(
      refresh: true,
      requestedCategoryId: categoryId,
      switchFilter: true,
    );
  }

  Future<void> selectSearch(String search) async {
    if (_disposed || loading || selectedSearch == search) return;
    await _load(refresh: true, requestedSearch: search, switchFilter: true);
  }

  Future<void> _load({
    required bool refresh,
    int? requestedCategoryId,
    String? requestedSearch,
    bool switchFilter = false,
  }) async {
    if (_disposed || loading) return;
    if (!refresh && isExpired) {
      _expire();
      return;
    }
    if (!refresh && nextPage == null) return;
    final generation = ++_generation;
    final categoryId = switchFilter ? requestedCategoryId : selectedCategoryId;
    final search = switchFilter ? requestedSearch : selectedSearch;
    if (switchFilter) {
      _expiryTimer?.cancel();
      _items.clear();
      _notices.clear();
      _categories.clear();
      selectedCategoryId = categoryId;
      selectedSearch = search;
      snapshot = null;
      nextPage = null;
      expiresAt = null;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await _api.fetchPage(
        page: refresh ? 1 : nextPage!,
        snapshot: refresh ? null : snapshot,
        categoryId: categoryId,
        search: search,
      );
      if (_disposed || generation != _generation) return;
      if ((!refresh && result.snapshot != snapshot) ||
          !DateTime.now().isBefore(result.expiresAt)) {
        _expire();
        return;
      }
      if (refresh) {
        _items.clear();
        _notices.clear();
        _categories.clear();
      }
      final ids = _items.map((item) => item.id).toSet();
      _items.addAll(result.items.where((item) => ids.add(item.id)));
      _notices.addAll(result.notices);
      if (refresh) _categories.addAll(result.categories);
      selectedCategoryId = categoryId;
      selectedSearch = search;
      snapshot = result.snapshot;
      nextPage = result.nextPage;
      environment = result.environment;
      expiresAt = result.expiresAt;
      _expiryTimer?.cancel();
      _expiryTimer = Timer(
        result.expiresAt.difference(DateTime.now()),
        _expire,
      );
    } on WallpaperApiException catch (failure) {
      if (_disposed || generation != _generation) return;
      if (failure.kind == WallpaperFailure.expired) {
        _expire();
      } else {
        error = failure;
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _expire() {
    if (_disposed) return;
    ++_generation; // A response already in flight must not resurrect expired data.
    _expiryTimer?.cancel();
    _items.clear();
    _notices.clear();
    _categories.clear();
    _catalogCategories.clear();
    selectedCategoryId = null;
    selectedSearch = null;
    snapshot = null;
    nextPage = null;
    expiresAt = null;
    environment = null;
    loading = false;
    error = const WallpaperApiException(
      WallpaperFailure.expired,
      'This selection expired. Reload to see current wallpapers.',
    );
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isExpired) _expire();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _expiryTimer?.cancel();
    _api.close();
    super.dispose();
  }
}
