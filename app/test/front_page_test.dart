import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/state/history_recorder.dart';
import 'package:dasha_news/ui/pages/home_page.dart';
import 'package:dasha_news/widgets/story_card.dart';

/// The regression test for the blank front page.
///
/// The symptom was a release build showing a grey content area while the
/// newsroom was perfectly healthy. The cause was `DateFormat(..., 'en_IN')`
/// throwing `LocaleDataException` from inside the list's item builder —
/// `main()` never called `initializeDateFormatting` — and a release build
/// renders a failed list item as a blank ErrorWidget rather than crashing.
///
/// This deliberately does **not** load the locale data, and each test file runs
/// in its own isolate, so it exercises the fail-safe path: whatever intl has
/// loaded, the front page must still draw its stories.
void main() {
  testWidgets('the front page draws its stories even with no locale data',
      (tester) async {
    SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
    final prefs = await SharedPreferences.getInstance();
    final cache = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('dasha_front_page'),
    ))!;
    addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));

    final app = AppState(
      storage: _NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          String body;
          if (request.url.path.contains('developing')) {
            body = _feedJson(3, developing: true);
          } else if (request.url.path.contains('feed')) {
            body = _feedJson(6);
          } else {
            body = '{"status":"ok"}';
          }
          return http.Response(body, 200,
              headers: const {'content-type': 'application/json'});
        }),
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

    // The assertion that the blank screen broke: the list mounted, but no item
    // was ever built.
    expect(find.byType(StoryCard), findsWidgets);
    expect(find.textContaining('తెలంగాణ'), findsWidgets);

    // And no exception escaped into the tree.
    expect(tester.takeException(), isNull);
  });
}

/// The cache write is real `dart:io` I/O, which never completes when it is
/// scheduled inside a widget test's fake-async zone on this host. Stubbing it
/// keeps the test on the render path, which is what it is for.
class _NoDiskStorage extends Storage {
  _NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
}

String _feedJson(int count, {bool developing = false}) {
  final items = List.generate(count, (i) {
    return {
      'id': 900 + i,
      'cluster_id': 'cluster-$i',
      'slug': 'story-$i',
      'section': 'telangana',
      'section_label_te': 'తెలంగాణ',
      'section_label_en': 'Telangana',
      'status': 'published',
      'status_label_te': 'ప్రచురితం',
      'importance': 0.8 - i * 0.05,
      'evidence_score': 0.7,
      'num_sources': 3,
      'is_breaking': false,
      'is_developing': developing,
      'headline_te': 'తెలంగాణ తాజా వార్త ${i + 1}',
      'headline_en': 'Telangana news ${i + 1}',
      'lead_te': 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
      'district': 'Hyderabad',
      'state': 'Telangana',
      // Old enough to fall past the relative buckets and into DateFormat.
      'published_at': '2025-03-04T14:30:00',
      'updated_at': '2025-03-04T14:31:00',
    };
  });
  return json.encode({
    'items': items,
    'total': count,
    'page': 1,
    'page_size': 20,
    'has_more': false,
  });
}
