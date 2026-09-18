/// The desk's queue, held as one observable list.
///
/// The newsroom deliberately front-loads what needs a person -- held, failed
/// and needs-review stories first -- so an error cannot sit unnoticed at the
// bottom of page two. This state mirrors that ordering and adds a local
/// refresh, because after an action the queue's truth has changed.
library;

import 'package:flutter/foundation.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/models/story.dart';

enum WorkQueueTab { attention, all, manual, pipeline }

class WorkQueueState extends ChangeNotifier {
  WorkQueueState(this._client);

  final EditorApiClient _client;

  WorkQueueTab _tab = WorkQueueTab.attention;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<StoryDetail> _items = const [];
  int _total = 0;
  bool _hasMore = false;

  WorkQueueTab get tab => _tab;
  bool get loading => _loading;
  String? get error => _error;
  List<StoryDetail> get items => _items;
  int get total => _total;
  bool get canLoadMore => _hasMore && !_loadingMore;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _fetch(page: 1);
      _items = page.items;
      _total = page.total;
      _hasMore = page.hasMore;
    } on EditorApiException catch (exc) {
      _error = exc.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _fetch(page: (_items.length ~/ 25) + 1);
      _items = [..._items, ...page.items];
      _hasMore = page.hasMore;
    } on EditorApiException catch (exc) {
      _error = exc.message;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<Page<StoryDetail>> _fetch({required int page}) async {
    switch (_tab) {
      case WorkQueueTab.attention:
        return _client.stories(needsAttention: true, page: page);
      case WorkQueueTab.all:
        return _client.stories(page: page);
      case WorkQueueTab.manual:
        return _client.stories(origin: 'manual', page: page);
      case WorkQueueTab.pipeline:
        // The pipeline tab is the failures view; the queue itself is empty
        // there and the page renders the failure list instead.
        return Page<StoryDetail>(items: const [], total: 0, hasMore: false);
    }
  }

  void selectTab(WorkQueueTab tab) {
    if (_tab == tab) return;
    _tab = tab;
    _items = const [];
    _total = 0;
    _hasMore = false;
    _error = null;
    notifyListeners();
    refresh();
  }

  /// Replace a story in place after an edit, so the queue does not reorder
  /// or flash on every save.
  void upsert(StoryDetail story) {
    final index = _items.indexWhere((item) => item.id == story.id);
    if (index >= 0) {
      _items = List.of(_items)..[index] = story;
    } else {
      _items = [story, ..._items];
      _total += 1;
    }
    notifyListeners();
  }

  void drop(int storyId) {
    _items = _items.where((item) => item.id != storyId).toList(growable: false);
    _total = _items.length;
    notifyListeners();
  }
}
