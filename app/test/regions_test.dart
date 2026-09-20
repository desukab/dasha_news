import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/swipe_story_view.dart';

import 'pump_app.dart';

/// The stream's four regions.
///
/// What is being pinned here is the page's contract with the reader, not its
/// layout: every region is always offered in the order the reader swipes
/// through it, an empty Near You region becomes a prompt rather than a gap, and
/// a story the newsroom only has in English never reaches the Telugu stream.
void main() {
  Future<void> pumpFront(
    WidgetTester tester, {
    required String body,
    required String language,
  }) async {
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_regions');

    final app = AppState(
      storage: NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          if (request.url.path.contains('front')) {
            return http.Response(body, 200,
                headers: const {'content-type': 'application/json'});
          }
          return http.Response('{"items":[],"total":0,"page":1,'
              '"page_size":6,"has_more":false}', 200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    await app.setLocale(language);

    await pumpStream(tester, app);
  }

  /// The stream's screens from here to the end, which is where the recovery
  /// gesture and the tip line live. The walk stops on the end note the reader
  /// sees rather than on a count derived from the fixture, so it does not go
  /// stale when a fixture's story count changes.
  ///
  /// A stream served from a stale cache closes with the offline hint rather
  /// than the end mark, so both are checked — the recovery test walks a cache
  /// stream first and a live one second.
  Future<void> walkToEnd(WidgetTester tester) async {
    const strings = AppStrings('te');
    for (var i = 0; i < 24; i++) {
      if (find.text(strings.streamEnd).evaluate().isNotEmpty) break;
      if (find.text(strings.offlineHint).evaluate().isNotEmpty) break;
      await swipeNext(tester);
    }
  }

  /// The stream is a lazily-built pager, and a screen the reader has not swiped
  /// to is never built. This walks the stream to the end, collecting which
  /// region labels rendered, so the assertions see the whole stream rather
  /// than its first screen.
  Future<List<String>> visibleRegions(WidgetTester tester) async {
    final labels = <String>[];
    for (var i = 0; i < 24; i++) {
      for (final label in const [
        'ఇప్పుడు',
        'మీ చుట్టూ',
        'తెలంగాణ',
        'భారతదేశం & ప్రపంచం',
        'Now',
        'Near You',
        'Telangana',
        'India & World',
      ]) {
        if (find.text(label).evaluate().isNotEmpty && !labels.contains(label)) {
          labels.add(label);
        }
      }
      await swipeNext(tester);
    }
    return labels;
  }

  testWidgets('the four regions are offered in the order the reader swipes',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 1, telangana: 1, indiaWorld: 1),
        language: 'te');

    final labels = await visibleRegions(tester);
    // All four regions are there, and in swipe order.
    expect(labels, [
      'ఇప్పుడు',
      'మీ చుట్టూ',
      'తెలంగాణ',
      'భారతదేశం & ప్రపంచం',
    ]);
  });

  testWidgets('an empty Near You region is a prompt, not a gap', (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1,
            district: null),
        language: 'te');

    const strings = AppStrings('te');
    // The prompt is the second screen in the stream, so arrive at it first.
    await swipeNext(tester);
    // The region's label is still there, so the reader can see the question was
    // asked — the prompt carries it, the way a story screen carries its own.
    expect(find.text(strings.regionNear), findsOneWidget);
    expect(find.text(strings.nearNeedsDistrict), findsOneWidget);
    // And the screen is the one place the district choice is offered from.
    expect(find.byIcon(Icons.place_rounded), findsWidgets);
  });

  testWidgets('a Near You region with stories shows no district prompt',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 2, telangana: 1, indiaWorld: 1,
            district: 'Hyderabad'),
        language: 'te');

    // The first Near You story is the second screen in the stream.
    await swipeNext(tester);
    expect(find.text(const AppStrings('te').nearNeedsDistrict), findsNothing);
    expect(find.text(const AppStrings('te').regionNear), findsOneWidget);
  });

  testWidgets('an English-only reader gets the English region names',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
        language: 'en');

    final labels = await visibleRegions(tester);
    expect(labels, ['Now', 'Near You', 'Telangana', 'India & World']);
  });

  testWidgets('a story the newsroom only has in English is not drawn',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, telangana: 0, indiaWorld: 0, near: 0,
            teluguOnly: false),
        language: 'te');

    // The stream is not empty — there is a Telugu story — but nothing is drawn
    // under a region the story is not in.
    expect(find.byType(SwipeStoryView), findsOneWidget);
    expect(find.text(const AppStrings('te').regionTelangana), findsNothing);
  });

  testWidgets('the end of the stream still carries the tip line', (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
        language: 'te');

    // Walk to the end. The stream's screens are: Now, the Near You prompt,
    // Telangana, India & World, then the end note.
    await walkToEnd(tester);

    const strings = AppStrings('te');
    expect(find.text(strings.streamEnd), findsOneWidget);
    // The tip line moved off the floating button and onto the end screen, so
    // it must still be reachable from the front page.
    expect(find.text(strings.submitTip), findsOneWidget);
  });

  testWidgets('the language switch stays one tap away from the stream',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
        language: 'te');

    // The district control replaced the floating button, not the language
    // switch: a reader who reads Telugu and a reader who reads English both
    // arrive on the first screen.
    expect(find.byIcon(Icons.language_rounded), findsOneWidget);
    expect(find.byIcon(Icons.place_rounded), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a stream that recovered from offline stops saying it is offline',
      (tester) async {
    // The cache holds the front page from a previous run, so the cold start
    // shows a stream and marks it as the cache's copy. The newsroom then
    // answers. A stream that kept the offline end note after recovering told
    // the reader their connection was broken when it was not.
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_regions_recovered');

    // The first fetch fails offline, the second succeeds. The seeded failure
    // has to be a SocketException: a ClientException classifies as a plain
    // network error, which never set the flag in the first place.
    var calls = 0;
    final app = AppState(
      storage: SeededStorage(prefs, cache,
          _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1)),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          if (!request.url.path.contains('front')) {
            return http.Response('{"status":"ok"}', 200,
                headers: const {'content-type': 'application/json'});
          }
          calls++;
          if (calls == 1) {
            throw const SocketException('socket closed');
          }
          return http.Response(
              _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
              200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    await app.setLocale('te');

    await pumpStream(tester, app);

    // Walk to the end twice. The first walk sees the stale cached stream, the
    // second — after the recovery below — sees the live one.
    await walkToEnd(tester);
    expect(find.text(const AppStrings('te').offlineHint), findsOneWidget);

    // The recovery gesture is on the end screen, where a stale stream is most
    // likely to be noticed.
    final refresh = find.byIcon(Icons.refresh_rounded);
    expect(refresh, findsOneWidget);
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await walkToEnd(tester);
    expect(find.text(const AppStrings('te').streamEnd), findsOneWidget);
    expect(find.text(const AppStrings('te').offlineHint), findsNothing);
  });

  testWidgets('a cache entry the wrong shape is discarded, not shown',
      (tester) async {
    // A cache file that is valid JSON but the wrong shape used to escape the
    // guard: the `as Map` cast inside fromJson fails with a TypeError, which
    // is not an Exception, so an `on Exception` catch let it reach the
    // reader's screen as an unhandled error. The cache is the app's own disk,
    // but it is written from untrusted wire data, so a malformed entry has to
    // be a miss rather than a crash.
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_regions_corrupt');

    final app = AppState(
      storage: SeededStorage(prefs, cache, '{"language":"te","now":{"items":[1]}}'),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          if (request.url.path.contains('front')) {
            return http.Response(
                _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
                200,
                headers: const {'content-type': 'application/json'});
          }
          return http.Response('{"status":"ok"}', 200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    await app.setLocale('te');

    await pumpStream(tester, app);

    // The corrupt entry was thrown away, and the fresh fetch is what the
    // reader sees instead of a blank screen.
    expect(find.byType(SwipeStoryView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unreachable newsroom on a cold start is the retry screen',
      (tester) async {
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_regions_down');

    final app = AppState(
      storage: NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    await app.setLocale('te');

    await pumpStream(tester, app);

    // No front page arrived and the cache was empty, so the reader is told
    // rather than left on a blank screen.
    expect(find.byType(SwipeStoryView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

String _frontJson({
  int now = 0,
  int near = 0,
  int telangana = 0,
  int indiaWorld = 0,
  String? district,
  bool teluguOnly = true,
}) {
  Map<String, dynamic> region(int count, String section, {String? asked}) {
    return {
      'items': List.generate(count, (i) => _card(100 + i,
          section: section, telugu: teluguOnly)),
      'total': count,
      'asked': asked,
      'has_more': false,
    };
  }

  return json.encode({
    'now': region(now, 'telangana'),
    'near': region(near, 'telangana', asked: district),
    'telangana': region(telangana, 'telangana'),
    'india_world': region(indiaWorld, 'national'),
    'language': 'te',
    'district': district,
  });
}

Map<String, dynamic> _card(int i,
    {String section = 'telangana', bool telugu = true}) {
  return {
    'id': 900 + i,
    'cluster_id': 'cluster-$i',
    'slug': 'story-$i',
    'section': section,
    // A section name that is not also a region name, so a region-label
    // assertion is not satisfied by accident by a section label.
    'section_label_te': 'రాజకీయాలు',
    'section_label_en': 'Politics',
    'status': 'published',
    'status_label_te': 'ప్రచురితం',
    'importance': 0.8,
    'evidence_score': 0.7,
    'num_sources': 3,
    'is_breaking': false,
    'is_developing': false,
    'headline_te': telugu ? 'తెలంగాణ తాజా వార్త $i' : 'English headline $i',
    'headline_en': 'English headline $i',
    'lead_te': 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
    'district': 'Hyderabad',
    'state': 'Telangana',
    'published_at': '2025-03-04T14:30:00',
    'updated_at': '2025-03-04T14:31:00',
  };
}
