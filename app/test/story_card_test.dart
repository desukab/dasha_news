import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/models/story.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/story_card.dart';

/// The card is what a reader scans a page by, so it is tested for what it owes
/// the reader — the headline, the summary, where and when — and for what it
/// must not show. Evidence levels, confidence scores, source counts and
/// conflict flags are the desk's machinery; a reader who never opens a story
/// should not have to read a dashboard to scroll past one.
void main() {
  testWidgets('a card draws no editorial machinery', (tester) async {
    await _pumpCard(tester, _story());

    // Provenance and evidence live on the desk's pages, not in the feed.
    expect(find.byIcon(Icons.verified_rounded), findsNothing);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.textContaining('%'), findsNothing);
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

  testWidgets('the headline falls back rather than rendering blank',
      (tester) async {
    await _pumpCard(tester, _story(headlineTe: 'తెలంగాణ వార్త'), locale: 'en');
    // An English reader with no English headline still sees something.
    expect(find.text('తెలంగాణ వార్త'), findsOneWidget);
  });

  testWidgets('the meta line carries the district and the relative time',
      (tester) async {
    await _pumpCard(
      tester,
      _story(
        sectionLabelEn: 'Politics',
        district: 'Warangal',
        publishedAt: DateTime.now(),
      ),
    );
    // Only the section label is set in caps, the way a folio line reads; a
    // district is a proper noun and keeps its own case.
    expect(find.textContaining('POLITICS · Warangal ·'), findsOneWidget);
    expect(find.textContaining('just now'), findsOneWidget);
  });

  testWidgets('the meta line does not pass a bare state off as a location',
      (tester) async {
    await _pumpCard(
      tester,
      _story(sectionLabelEn: 'Politics', publishedAt: DateTime.now()),
    );
    // Every story is filed from Telangana; naming the state on every card
    // teaches the reader nothing, so only a district or a mandal is a place.
    expect(find.textContaining('POLITICS · just now'), findsOneWidget);
    expect(find.textContaining('POLITICS · TELANGANA'), findsNothing);
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

  // -- the front page variants ------------------------------------------------

  testWidgets('a lead variant shows the lead paragraph and a full-width photo',
      (tester) async {
    await _pumpCard(
      tester,
      _story(
        headlineTe: 'తెలంగాణ తాజా వార్త',
        imageUrl: 'https://newsroom.test/photo.jpg',
        bodyTe: 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
      ),
      variant: StoryVariant.lead,
    );

    // The lead is the one variant that carries the photograph and the
    // summary paragraph.
    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.textContaining('మొదటి వాక్యం'), findsOneWidget);
  });

  testWidgets('a standard variant shows headline, summary and thumbnail',
      (tester) async {
    await _pumpCard(
      tester,
      _story(
        headlineTe: 'తెలంగాణ తాజా వార్త',
        imageUrl: 'https://newsroom.test/photo.jpg',
        bodyTe: 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
      ),
      variant: StoryVariant.standard,
    );

    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text('తెలంగాణ తాజా వార్త'), findsOneWidget);
    expect(find.textContaining('మొదటి వాక్యం'), findsOneWidget);
  });

  testWidgets('a brief variant is type only — no card, no photo, no summary',
      (tester) async {
    await _pumpCard(
      tester,
      _story(
        imageUrl: 'https://newsroom.test/photo.jpg',
        bodyTe: 'ఇది మొదటి వాక్యం. రెండవ వాక్యం ఇది.',
      ),
      variant: StoryVariant.brief,
    );

    expect(find.byType(Card), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
    // The brief keeps the headline and drops the summary.
    expect(find.textContaining('మొదటి వాక్యం'), findsNothing);
  });

  testWidgets('compact: true is the brief variant', (tester) async {
    await _pumpCard(tester, _story(), compact: true);
    expect(find.byType(Card), findsNothing);
  });
}

Future<void> _pumpCard(
  WidgetTester tester,
  Story story, {
  VoidCallback? onTap,
  String locale = 'en',
  StoryVariant? variant,
  bool compact = false,
}) async {
  final app = await _appState(tester, locale: locale);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StoryCard(
            story: story,
            onTap: onTap,
            variant: variant,
            compact: compact,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
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
  bool isBreaking = false,
  bool isDeveloping = false,
  String? headlineTe,
  String? headlineEn,
  String sectionLabelEn = 'Telangana',
  String? district,
  String? imageUrl,
  DateTime? publishedAt,
  String? bodyTe,
}) {
  return Story(
    id: id,
    clusterId: 'c',
    slug: 'slug-$id',
    section: 'telangana',
    status: 'published',
    importance: 0.5,
    isBreaking: isBreaking,
    isDeveloping: isDeveloping,
    // headlineEn is left null by default: a story with an English column
    // gives an English reader English, which is what the gate is for, and
    // the fallback tests need a story that has no English to fall back on.
    headlineTe: headlineTe ?? 'తెలంగాణ వార్త',
    headlineEn: headlineEn,
    sectionLabelTe: 'తెలంగాణ',
    sectionLabelEn: sectionLabelEn,
    district: district,
    state: 'Telangana',
    imageUrl: imageUrl,
    publishedAt: publishedAt ?? DateTime(2025, 3, 4, 14, 30),
    bodyTe: bodyTe,
  );
}
