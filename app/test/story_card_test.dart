import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/models/story.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/story_card.dart';

/// The card is the editorial contract made visible: a reader who never opens
/// a story should still be able to read its evidence from the card alone.
void main() {
  testWidgets('a corroborated story shows its source count and evidence',
      (tester) async {
    await _pumpCard(
      tester,
      _story(numSources: 3, evidenceScore: 0.9),
      facts: [_fact('fact')],
    );

    expect(find.textContaining('3'), findsWidgets);
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    // A story whose outlets agree carries no conflict marker.
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('a single-source story is marked as uncorroborated',
      (tester) async {
    await _pumpCard(tester, _story(numSources: 1, evidenceScore: 0.2));

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.verified_rounded), findsNothing);
  });

  testWidgets('a conflict between sources is shown, never hidden',
      (tester) async {
    await _pumpCard(
      tester,
      _story(
        numSources: 2,
        sources: const [
          SourceLink(id: 1, corroborates: false, conflictsWith: 'toll figure'),
          SourceLink(id: 2, corroborates: true),
        ],
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });

  testWidgets(
      'a story without a fact list drops the evidence chip rather than guessing',
      (tester) async {
    await _pumpCard(tester, _story());
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });

  testWidgets('a breaking story is badged above the fold', (tester) async {
    await _pumpCard(tester, _story(isBreaking: true));
    expect(find.text('BREAKING'), findsOneWidget);
  });

  testWidgets('a developing story is badged only when not breaking',
      (tester) async {
    await _pumpCard(tester, _story(isDeveloping: true));
    expect(find.text('DEVELOPING'), findsOneWidget);

    await _pumpCard(tester, _story(isBreaking: true, isDeveloping: true));
    expect(find.text('DEVELOPING'), findsNothing);
    expect(find.text('BREAKING'), findsOneWidget);
  });

  testWidgets('a corrected story points at its correction', (tester) async {
    await _pumpCard(tester, _story(correctionsCount: 1));
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('the headline falls back rather than rendering blank',
      (tester) async {
    await _pumpCard(tester, _story(headlineTe: 'తెలంగాణ వార్త'), locale: 'en');
    // An English reader with no English headline still sees something.
    expect(find.text('తెలంగాణ వార్త'), findsOneWidget);
  });

  testWidgets('tapping the card calls back with its story', (tester) async {
    final story = _story();
    Story? tapped;
    await _pumpCard(tester, story, onTap: () => tapped = story);
    await tester.tap(find.byType(StoryCard));
    await tester.pump();
    expect(tapped, story);
  });

  testWidgets('a story without an image renders without a thumbnail',
      (tester) async {
    await _pumpCard(tester, _story());
    expect(find.byIcon(Icons.image_outlined), findsNothing);
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  Story story, {
  VoidCallback? onTap,
  String locale = 'en',
  List<Fact> facts = const [],
}) async {
  final app = await _appState(tester, locale: locale);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StoryCard(
            story: story.copyWithDetail(_withFacts(story, facts)),
            onTap: onTap,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Story _withFacts(Story story, List<Fact> facts) {
  return Story(
    id: story.id,
    clusterId: story.clusterId,
    slug: story.slug,
    section: story.section,
    status: story.status,
    importance: story.importance,
    evidenceScore: story.evidenceScore,
    numSources: story.numSources,
    isBreaking: story.isBreaking,
    isDeveloping: story.isDeveloping,
    // These belong on the card's story too: the conflict and correction chips
    // are read from them, and dropping them here silently weakened the tests.
    correctionsCount: story.correctionsCount,
    sources: story.sources,
    headlineTe: story.headlineTe,
    imageUrl: story.imageUrl,
    facts: facts,
  );
}

/// A real [AppState] wired to an unreachable newsroom, so the card sees the
/// same state shape it does in the app without any network or disk effects.
///
/// The cache directory is a plain [Directory] rather than
/// `getTemporaryDirectory()`: the path_provider plugin is not available in the
/// headless tester and would hang the run. Creating it under
/// [WidgetTester.runAsync] matters too: a widget test runs inside a fake-async
/// zone, and real `dart:io` file I/O scheduled there never completes on this
/// host, which hangs the whole run. The card never reads the cache, so this is
/// the only disk the test touches.
Future<AppState> _appState(WidgetTester tester, {required String locale}) async {
  SharedPreferences.setMockInitialValues({localeKey: locale});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_test_cache'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  final state = AppState(
    storage: Storage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      client: MockClient((_) async => throw Exception('no network in tests')),
    ),
  );
  // The stored locale is only hydrated inside init(), which these tests do not
  // call: it would reach the network and the connectivity plugin. Setting the
  // language through the app's own setter keeps the card reading the same state
  // a running app would have, rather than the default.
  await state.setLocale(locale);
  return state;
}

Story _story({
  int id = 1,
  int numSources = 2,
  double evidenceScore = 0.5,
  bool isBreaking = false,
  bool isDeveloping = false,
  int correctionsCount = 0,
  String? headlineTe,
  List<SourceLink> sources = const [],
}) {
  return Story(
    id: id,
    clusterId: 'c',
    slug: 'slug-$id',
    section: 'telangana',
    status: 'published',
    importance: 0.5,
    evidenceScore: evidenceScore,
    numSources: numSources,
    isBreaking: isBreaking,
    isDeveloping: isDeveloping,
    headlineTe: headlineTe ?? 'Telangana news',
    correctionsCount: correctionsCount,
    sources: sources,
    imageUrl: null,
  );
}

Fact _fact(String level) {
  return Fact(
    id: 1,
    textTe: 'వాక్యం',
    evidenceLevel: level,
    confidence: 0.9,
    status: 'active',
    rank: 1,
  );
}
