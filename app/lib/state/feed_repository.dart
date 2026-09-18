import 'dart:convert';

import '../core/api_client.dart';
import '../models/page.dart';
import 'app_state.dart';

/// One screen's worth of fetching plus its offline cache.
///
/// Each tab owns one of these. The contract is uniform: the tab asks for a
/// page, it returns real data or the last good data it had, and it says which
/// of the two happened via [StoryPage.fromCache].
class FeedRepository {
  FeedRepository(this.appState, this.cacheName);

  final AppState appState;
  final String cacheName;

  bool _cacheInitialised = false;
  StoryPage? _lastGood;

  /// Fetches a page, falling back to the cache when the newsroom is
  /// unreachable and nothing else can be shown.
  Future<StoryPage> fetch({
    required Future<StoryPage> Function() load,
  }) async {
    try {
      final page = await load();
      _lastGood = page;
      await _persist(page);
      return page;
    } on ApiException catch (exc) {
      if (exc.isOffline || exc.kind == ApiFailure.network) {
        final cached = await _readCache();
        if (cached != null) {
          return cached;
        }
      }
      rethrow;
    }
  }

  /// The most recent page fetched, loaded from disk on first use.
  Future<StoryPage?> lastGood() async {
    if (_lastGood != null) return _lastGood;
    if (_cacheInitialised) return null;
    _cacheInitialised = true;
    _lastGood = await _readCache();
    return _lastGood;
  }

  Future<void> _persist(StoryPage page) async {
    if (page.items.isEmpty) return;
    await appState.storage.putCache(
      cacheName,
      jsonEncode({
        'items': page.items.map((story) => story.toJson()).toList(),
        'total': page.total,
        'page': page.page,
        'page_size': page.pageSize,
        'has_more': page.hasMore,
        'language': appState.locale,
      }),
    );
  }

  Future<StoryPage?> _readCache() async {
    try {
      final raw = await appState.storage.getCache(cacheName);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return StoryPage.fromJson(decoded).copyWith(fromCache: true);
    } on Exception {
      // A corrupt cache is discarded, not shown.
      return null;
    }
  }

  Future<void> clear() async {
    _lastGood = null;
    await appState.storage.putCache(cacheName, '');
  }
}

/// Cache names, shared so a screen and its repository always agree.
class CacheNames {
  const CacheNames._();

  static const String feed = 'feed';
  static const String breaking = 'breaking';
  static const String developing = 'developing';
  static const String search = 'search';
  static const String sections = 'sections';
}
