import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/models/page.dart';
import 'package:dasha_news/models/story.dart';
import 'package:dasha_news/state/paged_list.dart';

/// Pagination is where the app's offline promise is kept or broken: a failed
/// request must never cost the reader the stories already on screen.
void main() {
  test('a refresh replaces the whole list', () async {
    final list = PagedList((page) async => _page([_story(1), _story(2)]));
    await list.refresh();
    expect(list.items.map((s) => s.id), [1, 2]);
    expect(list.isLoading, isFalse);
    expect(list.error, isNull);
    list.dispose();
  });

  test('loadMore appends and stops when the newsroom says there is no more',
      () async {
    final list = PagedList((page) async => _page([_story(page)], page: page, hasMore: page < 3));
    await list.refresh();
    expect(list.hasMore, isTrue);
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1, 2]);
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1, 2, 3]);
    expect(list.hasMore, isFalse);
    // Further calls are no-ops.
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1, 2, 3]);
    list.dispose();
  });

  test('an empty page ends the iteration without clearing what was loaded',
      () async {
    final list = PagedList((page) async =>
        _page(page == 1 ? [_story(1)] : [], page: page));
    await list.refresh();
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1]);
    expect(list.hasMore, isFalse);
    list.dispose();
  });

  test('a story published mid-iteration is not shown twice', () async {
    // Page 2 re-includes story 1, as it can when the feed is re-sorted
    // between requests; the reader must never see the same story twice.
    final list = PagedList((page) async => _page(
          page == 1 ? [_story(1)] : [_story(2), _story(1)],
          page: page,
          hasMore: page == 1,
        ));
    await list.refresh();
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1, 2]);
    list.dispose();
  });

  test('a soft failure keeps the already-loaded items', () async {
    var calls = 0;
    final list = PagedList((page) async {
      calls++;
      if (page == 1) return _page([_story(1)], page: 1, hasMore: true);
      throw ApiException.offline();
    });
    await list.refresh();
    await list.loadMore();
    expect(list.items.map((s) => s.id), [1]);
    expect(list.error?.isOffline, isTrue);
    expect(list.isHardEmpty, isFalse);
    list.dispose();
  });

  test('a hard failure on the first load leaves nothing to show', () async {
    final list = PagedList((page) async => throw ApiException(400, 'bad'));
    await list.refresh();
    expect(list.items, isEmpty);
    expect(list.isHardEmpty, isTrue);
    expect(list.isEmpty, isTrue);
    list.dispose();
  });

  test('a cached page renders before the network answers and survives its failure',
      () async {
    final list = PagedList((page) async => throw ApiException.offline());
    await list.injectCached(_page([_story(9)], page: 1));
    expect(list.items.map((s) => s.id), [9]);
    await list.refresh();
    // The refresh failed softly, so the cached story is still on screen.
    expect(list.items.map((s) => s.id), [9]);
    expect(list.error?.isOffline, isTrue);
    list.dispose();
  });

  test('replace updates a card in place and remove takes it away', () async {
    final list = PagedList((page) async => _page([_story(1), _story(2)]));
    await list.refresh();
    list.replace(_story(1));
    expect(list.items.first.id, 1);
    list.remove(2);
    expect(list.items.map((s) => s.id), [1]);
    // Unknown ids are ignored, not crashed on.
    list.remove(99);
    expect(list.items.map((s) => s.id), [1]);
    list.dispose();
  });

  test('a concurrent refresh is coalesced into one request', () async {
    var calls = 0;
    final list = PagedList((page) async {
      calls++;
      return _page([_story(1)]);
    });
    await Future.wait([list.refresh(), list.refresh()]);
    expect(calls, 1);
    list.dispose();
  });

  test('items is unmodifiable from the outside', () async {
    final list = PagedList((page) async => _page([_story(1)]));
    await list.refresh();
    expect(() => list.items.add(_story(2)), throwsUnsupportedError);
    list.dispose();
  });
}

StoryPage _page(List<Story> items, {int page = 1, bool hasMore = false}) {
  return StoryPage(
    items: items,
    total: items.length,
    page: page,
    pageSize: 20,
    hasMore: hasMore,
  );
}

Story _story(int id) {
  return Story(
    id: id,
    clusterId: 'c$id',
    slug: 'story-$id',
    section: 'telangana',
    status: 'published',
    importance: 0.5,
    evidenceScore: 0.5,
    numSources: 2,
    isBreaking: false,
    isDeveloping: false,
  );
}
