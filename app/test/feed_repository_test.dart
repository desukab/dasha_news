import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/models/page.dart';
import 'package:dasha_news/models/story.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/state/feed_repository.dart';

/// The offline cache is a promise: whatever it hands back must be an answer to
/// the question the screen is currently asking. These are the ways that
/// promise used to be broken — the audio tab and a section view both shared
/// the front page's cache, and no cache was ever checked against the language
/// it was fetched in.
void main() {
  test('a page fetched online is served again when the newsroom is down',
      () async {
    final app = await _appState();
    final repo = FeedRepository(app, CacheNames.feed);

    await repo.fetch(load: () async => _page([_story(1)]));
    final offline = await repo.fetch(load: _throwOffline);

    expect(offline.items.map((s) => s.id), [1]);
    expect(offline.fromCache, isTrue);
  });

  test('a cache written in one language is not served in another', () async {
    final app = await _appState();
    final repo = FeedRepository(app, CacheNames.feed);

    await repo.fetch(load: () async => _page([_story(1)]));
    await app.setLocale('en');

    // The cached page is Telugu; the reader is now reading English. Falling
    // back to it would put the wrong script on screen, so this is a miss.
    await expectLater(
      () => repo.fetch(load: _throwOffline),
      throwsA(isA<ApiException>()),
    );
  });

  test('a screen that asks a different question gets no other screen\'s cache',
      () async {
    final app = await _appState();

    // The front page was fetched and cached.
    final home = FeedRepository(app, CacheNames.feed);
    await home.fetch(load: () async => _page([_story(1)]));

    // The audio edition shares nothing with it: it has its own cache name, so
    // an offline audio list must fail rather than show the front page.
    final audio = FeedRepository(app, CacheNames.audio);
    await expectLater(
      () => audio.fetch(load: _throwOffline),
      throwsA(isA<ApiException>()),
    );
  });

  test('each section keeps its own cache', () async {
    final app = await _appState();

    final politics = FeedRepository(app, CacheNames.section('politics'));
    await politics.fetch(load: () async => _page([_story(11)]));

    final cinema = FeedRepository(app, CacheNames.section('cinema'));
    // Cinema offline has nothing of its own, and politics must not stand in
    // for it under a సినిమా header.
    await expectLater(
      () => cinema.fetch(load: _throwOffline),
      throwsA(isA<ApiException>()),
    );

    // Politics, meanwhile, is still served its own page.
    final again = await politics.fetch(load: _throwOffline);
    expect(again.items.map((s) => s.id), [11]);
  });

  test('each query keeps its own cache', () async {
    final app = await _appState();

    final floods = FeedRepository(app, CacheNames.search('floods'));
    await floods.fetch(load: () async => _page([_story(21)]));

    final elections = FeedRepository(app, CacheNames.search('elections'));
    await expectLater(
      () => elections.fetch(load: _throwOffline),
      throwsA(isA<ApiException>()),
    );
  });

  test('a corrupt cache is discarded rather than shown', () async {
    final app = await _appState();
    final repo = FeedRepository(app, CacheNames.feed);

    await app.storage.putCache(CacheNames.feed, 'not json at all');
    await expectLater(
      () => repo.fetch(load: _throwOffline),
      throwsA(isA<ApiException>()),
    );
  });

  test('clearCache forgets the per-section and per-query pages too', () async {
    final cache = await _cacheDir();
    final app = await _appState(cache: cache);

    await app.storage.putCache(CacheNames.feed, '{"items":[]}');
    await app.storage.putCache(CacheNames.audio, '{"items":[]}');
    await app.storage.putCache(CacheNames.section('cinema'), '{"items":[]}');
    await app.storage.putCache(CacheNames.search('floods'), '{"items":[]}');
    expect(cache.listSync().where(_isCacheFile).length, 4);

    await app.clearCache();
    expect(cache.listSync().where(_isCacheFile), isEmpty);
  });

  test('a failed fetch that is not offline does not touch the cache', () async {
    final app = await _appState();
    final repo = FeedRepository(app, CacheNames.feed);

    await repo.fetch(load: () async => _page([_story(1)]));
    // A 500 is the newsroom's problem, not the reader's connection; the old
    // page must not be swapped for it.
    await expectLater(
      () => repo.fetch(load: _throwServer),
      throwsA(isA<ApiException>()),
    );
    final cached = await repo.lastGood();
    expect(cached?.items.map((s) => s.id), [1]);
  });
}

bool _isCacheFile(FileSystemEntity entity) =>
    entity.uri.pathSegments.last.startsWith('dasha_cache_');

Future<StoryPage> _throwOffline() async => throw ApiException.offline('down');

Future<StoryPage> _throwServer() async => throw const ApiException(500, 'down');

StoryPage _page(List<Story> items, {int page = 1, bool hasMore = false}) =>
    StoryPage(
      items: items,
      total: items.length,
      page: page,
      pageSize: 20,
      hasMore: hasMore,
    );

Story _story(int id) => Story(
      id: id,
      clusterId: '$id',
      slug: 'story-$id',
      section: 'state',
      status: 'published',
      importance: 1.0,
      evidenceScore: 0,
      numSources: 1,
      isBreaking: false,
      isDeveloping: false,
    );

/// A real [AppState] with an isolated cache directory, so these tests exercise
/// the file cache itself rather than a stub of it. Created outside a
/// widget-test zone, so plain `dart:io` I/O completes normally here.
Future<AppState> _appState({Directory? cache}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(
    storage: Storage(prefs, cache ?? await _cacheDir()),
    api: ApiClient(baseUrl: 'http://newsroom.test'),
  );
  await state.setLocale('te');
  return state;
}

Future<Directory> _cacheDir() async {
  final dir = await Directory.systemTemp.createTemp('dasha_repo_test');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}
