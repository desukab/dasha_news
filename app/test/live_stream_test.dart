import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/swipe_story_view.dart';

import 'pump_app.dart';

/// The stream, against a real newsroom payload.
///
/// The fixture is a byte-for-byte capture of `/v1/front?language=te` from the
/// running newsroom, replayed through the transport the APK ships. A widget
/// test cannot make a real network call — `TestWidgetsFlutterBinding` answers
/// every `HttpClient` request with a 400, which is why a live pump is not
/// possible in this suite — but replaying the real bytes still exercises the
/// one thing a hand-written fixture cannot: the wire format the newsroom
/// actually emits, including the fields the stream reads and the order the
/// regions arrive in.
///
/// When the payload shape drifts, this test fails instead of the reader.
void main() {
  testWidgets('the stream renders the real newsroom payload', (tester) async {
    // The fixture read is real disk I/O and must happen inside runAsync, or it
    // never completes in the fake-async zone.
    final payload = (await tester.runAsync(_loadFixture))!;
    final prefs = await onboardedPrefs();
    final cache = await testCacheDir(tester, 'dasha_live_stream');

    final app = AppState(
      storage: NoDiskStorage(prefs, cache),
      api: ApiClient(
        baseUrl: 'https://newsroom.test',
        client: MockClient((request) async {
          if (request.url.path.contains('front')) {
            return http.Response(payload, 200,
                headers: const {'content-type': 'application/json'});
          }
          return http.Response('{"status":"ok"}', 200,
              headers: const {'content-type': 'application/json'});
        }),
      ),
    );
    await app.setLocale('te');

    await pumpStream(tester, app);

    // 13 stories across three regions plus the end screen.
    expect(find.byType(SwipeStoryView), findsWidgets);
    expect(find.text('ఇప్పుడు'), findsOneWidget);

    // The pager keeps the neighbouring screen built, and which ones are built
    // at any moment depends on settle timing. So the walk collects rather than
    // counts: every screen the stream ever mounted goes in a set as a
    // region-and-story pair, and every mounted headline is inspected, which
    // makes the assertions about what the reader would see rather than about
    // how many swipes happened.
    final seen = <(String, int)>{};
    final latinOnly = <int>{};
    final teluguScript = RegExp(r'[ఀ-౿]');
    for (var i = 0; i < 40; i++) {
      for (final element in find.byType(SwipeStoryView).evaluate()) {
        final view = element.widget as SwipeStoryView;
        final headline = view.story.headline('te');
        // A screen is a story *in a region*: the same story answers two of the
        // four questions and so appears twice, so the pair is what counts a
        // screen. Counting ids alone would cap the stream at the distinct
        // stories and hide a region the pager never built.
        seen.add((view.regionLabel, view.story.id));
        if (headline.isNotEmpty && !teluguScript.hasMatch(headline)) {
          latinOnly.add(view.story.id);
        }
      }
      // The reader knows the bulletin is over when the end mark is in front of
      // them, so the walk stops on what they see rather than on the pager's
      // internals. The end note is one screen past the last story, and a
      // settled pager only builds what overlaps the viewport, so it cannot
      // appear before every story screen has been built and sampled. The
      // forty iterations are a ceiling, not the plan.
      if (find.text(app.strings.streamEnd).evaluate().isNotEmpty) break;
      await swipeNext(tester);
    }

    // 13 screens across three regions: the Now and Telangana regions share
    // five stories between them, so this is a count of screens the pager
    // mounted, not of stories the newsroom has. A screen the pager failed to
    // build is a missing pair and a failing test rather than an off-by-one
    // nobody notices.
    expect(seen, hasLength(13));
    // A Telugu stream headline carries Telugu script. A Latin-only headline
    // means the language gate failed at the wire and an untranslated story is
    // being shown to a Telugu reader — a regression, not a style question.
    expect(latinOnly, isEmpty);
    expect(find.text(app.strings.streamEnd), findsOneWidget);
    expect(find.text(app.strings.submitTip), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<String> _loadFixture() async {
  final file = File('test/fixtures/live_front_te.json');
  return file.readAsString();
}
