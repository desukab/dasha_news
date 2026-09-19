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
      // A cached page is only reusable in the language it was fetched in —
      // the same story carries a different headline per language, and the
      // cache key carries no locale. A stale-language page is a miss, not an
      // answer in the wrong script.
      final language = decoded['language'];
      if (language is! String || language != appState.locale) return null;
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
///
/// A cache name is a promise about what is under the header it was fetched
/// for, so two screens that answer different questions never share one. The
/// per-query and per-section names are built rather than constant, because
/// the question is the reader's to change.
class CacheNames {
  const CacheNames._();

  static const String feed = 'feed';
  static const String breaking = 'breaking';
  static const String developing = 'developing';
  static const String sections = 'sections';

  /// The audio edition: stories the newsroom narrated, which is not the same
  /// set as the front page.
  static const String audio = 'audio';

  /// One cache per section: politics results must never surface under a
  /// సినిమా header when the newsroom is unreachable.
  static String section(String slug) => 'section:$slug';

  /// One cache per query: another search is not this search's answer.
  static String search(String query) => 'search:${query.trim()}';
}
