/// The reader-tip queue, held as one observable list.
///
/// A submission is a lead a person has to confirm, so this state never turns
/// a tip into a story on its own: it moves the triage label, and hands the
/// resulting draft back to the caller to open in the editor. The unread count
/// is the server's, so a tip triaged from another desk does not stay badged
/// here.
library;

import 'package:flutter/foundation.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/models/story.dart';

/// The filter the queue is showing. `new` is the default because a tip waiting
/// on nobody is the one the desk is behind on.
enum SubmissionFilter { all, newTips, triaged, verified, rejected }

extension SubmissionFilterLabel on SubmissionFilter {
  String get label {
    switch (this) {
      case SubmissionFilter.all:
        return 'All';
      case SubmissionFilter.newTips:
        return 'New';
      case SubmissionFilter.triaged:
        return 'Triaged';
      case SubmissionFilter.verified:
        return 'Verified';
      case SubmissionFilter.rejected:
        return 'Rejected';
    }
  }

  /// `null` asks the newsroom for every status.
  String? get asQuery {
    switch (this) {
      case SubmissionFilter.all:
        return null;
      case SubmissionFilter.newTips:
        return 'new';
      case SubmissionFilter.triaged:
        return 'triaged';
      case SubmissionFilter.verified:
        return 'verified';
      case SubmissionFilter.rejected:
        return 'rejected';
    }
  }
}

class SubmissionsState extends ChangeNotifier {
  SubmissionsState(this._client);

  final EditorApiClient _client;

  SubmissionFilter _filter = SubmissionFilter.newTips;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<SubmissionView> _items = const [];
  int _total = 0;
  bool _hasMore = false;
  int _newCount = 0;

  SubmissionFilter get filter => _filter;
  bool get loading => _loading;
  String? get error => _error;
  List<SubmissionView> get items => _items;
  int get total => _total;
  int get newCount => _newCount;
  bool get canLoadMore => _hasMore && !_loadingMore;

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _client.submissions(status: _filter.asQuery, page: 1);
      _apply(page);
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
      final page = await _client.submissions(
          status: _filter.asQuery, page: (_items.length ~/ 25) + 1);
      _items = [..._items, ...page.items];
      _hasMore = page.hasMore;
    } on EditorApiException catch (exc) {
      _error = exc.message;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  void _apply(SubmissionPage page) {
    _items = page.items;
    _total = page.total;
    _hasMore = page.hasMore;
    _newCount = page.newCount;
  }

  void selectFilter(SubmissionFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _items = const [];
    _total = 0;
    _hasMore = false;
    _error = null;
    notifyListeners();
    refresh();
  }

  /// Move a tip's triage label in place, so the list does not reorder when
  /// the desk clears it.
  Future<void> triage(int id, {required String status, String? note}) async {
    final before = _items;
    _error = null;
    notifyListeners();
    try {
      final updated = await _client.triageSubmission(id, status: status, note: note);
      _replace(updated);
      // The unread count is the server's to recompute; a tip that was new and
      // is no longer takes the badge down by one.
      if (before.firstWhere((t) => t.id == id, orElse: () => updated).status ==
              'new' &&
          status != 'new') {
        _newCount = (_newCount - 1).clamp(0, _newCount);
      }
    } on EditorApiException catch (exc) {
      _error = exc.message;
      notifyListeners();
      rethrow;
    }
  }

  /// Turn a tip into a draft. Returns the story the desk should open next.
  Future<StoryDetail> convert(int id,
      {String? headlineTe, String? section, String? district}) async {
    _error = null;
    notifyListeners();
    try {
      final story = await _client.submissionToStory(id,
          headlineTe: headlineTe, section: section, district: district);
      // The submission is now linked to a story; refresh keeps the row from
      // still offering a convert that the newsroom would refuse with a 409.
      await refresh();
      return story;
    } on EditorApiException catch (exc) {
      _error = exc.message;
      notifyListeners();
      rethrow;
    }
  }

  void _replace(SubmissionView updated) {
    final index = _items.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      _items = List.of(_items)..[index] = updated;
    }
    notifyListeners();
  }
}
