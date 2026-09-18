import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/page.dart';
import '../models/story.dart';

/// Pagination and error handling for any story list the app shows.
///
/// Every screen that displays a list of stories has the same shape: load the
/// first page, keep going until the newsroom says there is no more, and
/// survive a failed request by keeping what was already loaded. This class is
/// that shape, so the screens only differ in which endpoint they call.
class PagedList extends ChangeNotifier {
  PagedList(this._fetch);

  /// Returns one page of stories for the given page number.
  final Future<StoryPage> Function(int page) _fetch;

  final List<Story> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  ApiException? _error;
  int _total = 0;
  int _page = 0;

  List<Story> get items => List.unmodifiable(_items);

  bool get isLoading => _loading;

  bool get isLoadingMore => _loadingMore;

  bool get hasMore => _hasMore;

  bool get isEmpty => !_loading && _items.isEmpty;

  /// True when a hard failure left nothing to show.
  bool get isHardEmpty => _items.isEmpty && _error != null && !_error!.isOffline;

  ApiException? get error => _error;

  int get total => _total;

  /// Loads page 1, replacing everything.
  ///
  /// A failed refresh keeps the old items unless the failure is a hard error
  /// and nothing was loaded before; the reader should never lose what they
  /// already have to a transient network blip.
  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _fetch(1);
      _items
        ..clear()
        ..addAll(page.items);
      _page = 1;
      _total = page.total;
      _hasMore = page.hasMore && page.items.isNotEmpty;
    } on ApiException catch (exc) {
      _error = exc;
      if (exc.isClientError && exc.statusCode != 404) {
        _items.clear();
        _hasMore = false;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Appends the next page, if there is one and nothing is already loading.
  Future<void> loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _fetch(_page + 1);
      if (page.items.isEmpty) {
        _hasMore = false;
      } else {
        // The newsroom may have published a story mid-iteration; drop exact
        // duplicates rather than showing one twice.
        final seen = _items.map((story) => story.id).toSet();
        for (final story in page.items) {
          if (!seen.contains(story.id)) {
            _items.add(story);
          }
        }
        _page = page.page;
        _total = page.total;
        _hasMore = page.hasMore;
      }
    } on ApiException catch (exc) {
      _error = exc;
      // A failed "load more" is not a reason to empty the list.
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Shows a cache-loaded page immediately, before the network answers.
  ///
  /// A subsequent [refresh] replaces it. If the network is down, the refresh
  /// fails softly and the cached items survive.
  Future<void> injectCached(StoryPage cached) async {
    if (_loading || _items.isNotEmpty) return;
    _items.addAll(cached.items);
    _page = cached.page;
    _total = cached.total;
    _hasMore = cached.hasMore;
    notifyListeners();
  }

  /// Replaces a card with its freshly fetched detail, in place.
  void replace(Story updated) {
    final index = _items.indexWhere((story) => story.id == updated.id);
    if (index >= 0) {
      _items[index] = updated;
      notifyListeners();
    }
  }

  /// Removes a story, for the un-save flow.
  void remove(int storyId) {
    final index = _items.indexWhere((story) => story.id == storyId);
    if (index >= 0) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }
}
