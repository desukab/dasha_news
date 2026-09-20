import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/swipe_story_view.dart';

import 'pump_app.dart';

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
/// loaded, the stream must still draw its stories. The edition line at the end
/// of the stream is the one thing the page formats with `intl`, so it is on the
/// same render path as the stories, one swipe further along it.
void main() {
  testWidgets('the stream draws its stories even with no locale data',
      (tester) async {
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_front_page');

    final app = AppState(
      storage: NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          final body = request.url.path.contains('front')
              ? _frontJson()
              : '{"status":"ok"}';
          return http.Response(body, 200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    await app.setLocale('te');

    await pumpStream(tester, app);

    // The assertion that the blank screen broke: the pager mounted, but no
    // screen was ever built.
    expect(find.byType(SwipeStoryView), findsOneWidget);
    expect(find.textContaining('తెలంగాణ'), findsWidgets);

    // And no exception escaped into the tree.
    expect(tester.takeException(), isNull);
  });
}

/// The four regions the newsroom sends, with a story in each so every screen
/// the stream draws is reached.
String _frontJson() {
  Map<String, dynamic> region(List<Map<String, dynamic>> items,
      {String? asked}) {
    return {
      'items': items,
      'total': items.length,
      'asked': asked,
      'has_more': false,
    };
  }

  return json.encode({
    'now': region([_card(0)]),
    'near': region([_card(1)], asked: 'Hyderabad'),
    'telangana': region([_card(2)]),
    'india_world': region([_card(3, section: 'national')]),
    'language': 'te',
    'district': 'Hyderabad',
  });
}

Map<String, dynamic> _card(int i, {String section = 'telangana'}) {
  return {
    'id': 900 + i,
    'cluster_id': 'cluster-$i',
    'slug': 'story-$i',
    'section': section,
    'section_label_te': 'తెలంగాణ',
    'section_label_en': 'Telangana',
    'status': 'published',
    'status_label_te': 'ప్రచురితం',
    'importance': 0.8 - i * 0.05,
    'evidence_score': 0.7,
    'num_sources': 3,
    'is_breaking': false,
    'is_developing': false,
    'headline_te': 'తెలంగాణ తాజా వార్త ${i + 1}',
    'headline_en': 'Telangana news ${i + 1}',
    'lead_te': 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
    'district': 'Hyderabad',
    'state': 'Telangana',
    // Old enough to fall past the relative buckets and into DateFormat.
    'published_at': '2025-03-04T14:30:00',
    'updated_at': '2025-03-04T14:31:00',
  };
}
