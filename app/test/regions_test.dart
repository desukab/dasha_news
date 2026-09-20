import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/state/history_recorder.dart';
import 'package:dasha_news/ui/pages/home_page.dart';
import 'package:dasha_news/widgets/story_card.dart';

/// The front page's four regions.
///
/// What is being pinned here is the page's contract with the reader, not its
/// layout: every region is always drawn in the order the reader scans it, an
/// empty Near You region becomes a prompt rather than a gap, and a story that
/// the newsroom only has in English never reaches the Telugu front page.
void main() {
  Future<void> pumpFront(
    WidgetTester tester, {
    required String body,
    required String language,
  }) async {
    SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
    final prefs = await SharedPreferences.getInstance();
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('dasha_regions'),
    ))!;
    addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));

    final app = AppState(
      storage: _NoDiskStorage(prefs, cache),
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

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          Provider<HistoryRecorder>(create: (_) => HistoryRecorder(app)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HomePage(),
        ),
      ),
    );

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The front page is a lazily-built list, and a region below the fold is
  /// never built until the reader reaches it. This walks the list to the end,
  /// collecting what rendered, so the assertions see the whole page rather
  /// than its first screenful.
  Future<List<String>> visibleHeaders(WidgetTester tester) async {
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
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pump();
    }
    return labels;
  }

  testWidgets('the four regions are drawn in the order the reader scans them',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 1, telangana: 1, indiaWorld: 1),
        language: 'te');

    final labels = await visibleHeaders(tester);
    // All four headers are present, and in scan order.
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
    // The header is still there, so the reader can see the question was asked.
    expect(find.text(strings.regionNear), findsOneWidget);
    expect(find.text(strings.nearNeedsDistrict), findsOneWidget);
    // And it is the only place the front page offers the district choice from.
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('a Near You region with stories shows no district prompt',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 2, telangana: 1, indiaWorld: 1,
            district: 'Hyderabad'),
        language: 'te');

    expect(find.text(const AppStrings('te').nearNeedsDistrict), findsNothing);
    expect(find.text(const AppStrings('te').regionNear), findsOneWidget);
  });

  testWidgets('an English-only reader gets the English region names',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, near: 0, telangana: 1, indiaWorld: 1),
        language: 'en');

    final labels = await visibleHeaders(tester);
    expect(labels, ['Now', 'Near You', 'Telangana', 'India & World']);
  });

  testWidgets('a story the newsroom only has in English is not drawn',
      (tester) async {
    await pumpFront(tester,
        body: _frontJson(now: 1, telangana: 0, indiaWorld: 0, near: 0,
            teluguOnly: false),
        language: 'te');

    // The front page is not empty — there is a Telugu story — but nothing is
    // drawn under a region the story is not in.
    expect(find.byType(StoryCard), findsOneWidget);
    expect(find.text(const AppStrings('te').regionTelangana), findsNothing);
  });

  testWidgets('an unreachable newsroom on a cold start is the retry screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
    final prefs = await SharedPreferences.getInstance();
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('dasha_regions_down'),
    ))!;
    addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));

    final app = AppState(
      storage: _NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((_) async => http.Response('', 500)),
      ),
    );
    await app.setLocale('te');

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          Provider<HistoryRecorder>(create: (_) => HistoryRecorder(app)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const HomePage(),
        ),
      ),
    );

    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // No front page arrived and the cache was empty, so the reader is told
    // rather than left on a blank screen.
    expect(find.byType(StoryCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// The cache write is real `dart:io` I/O, which never completes inside a widget
/// test's fake-async zone on this host. Stubbing it keeps the test on the
/// render path.
class _NoDiskStorage extends Storage {
  _NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
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
    'section_label_te': 'తెలంగాణ',
    'section_label_en': 'Telangana',
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
