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
import 'package:dasha_news/state/audio_controller.dart';
import 'package:dasha_news/state/history_recorder.dart';
import 'package:dasha_news/ui/pages/saved_page.dart';
import 'package:dasha_news/widgets/states_view.dart';

/// The saved page holds its bookmarks on the server, so a failure here has to
/// be told apart from an honest empty list. A reader who is told "nothing
/// saved yet" when the newsroom merely returned a 500 is being told their
/// bookmarks are gone.
void main() {
  testWidgets('a failed fetch is not drawn as an empty bookmark list',
      (tester) async {
    final app = await _appState(tester, (request) async {
      return http.Response(
        jsonEncode({'detail': 'Internal Server Error: pool exhausted'}),
        500,
        headers: const {'content-type': 'application/json'},
      );
    });

    await _pump(tester, app);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final strings = AppStrings(app.locale);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text(strings.errorGeneric), findsNWidgets(2));
    expect(find.text(strings.bookmarksEmpty), findsNothing);
  });

  testWidgets('an offline fetch keeps the honest empty state', (tester) async {
    // Offline, the page genuinely cannot know what is saved, so it says so
    // rather than claiming the list is empty.
    final app = await _appState(tester, (request) async {
      throw const SocketException('no network in tests');
    });

    await _pump(tester, app);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ErrorState), findsNothing);
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('a saved story is drawn as a card', (tester) async {
    final app = await _appState(tester, (request) async {
      return http.Response(
        jsonEncode({
          'items': [_storyJson(31)],
          'total': 1,
          'page': 1,
          'page_size': 20,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    await _pump(tester, app);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('తెలంగాణ తాజా వార్త'), findsWidgets);
  });
}

Future<void> _pump(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<AudioController>(
          create: (_) => AudioController(app),
        ),
        Provider<HistoryRecorder>(create: (_) => HistoryRecorder(app)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SavedPage(),
      ),
    ),
  );
}

Map<String, dynamic> _storyJson(int id) => {
      'id': id,
      'cluster_id': 'cluster-$id',
      'slug': 'story-$id',
      'section': 'telangana',
      'section_label_te': 'తెలంగాణ',
      'section_label_en': 'Telangana',
      'status': 'published',
      'importance': 0.8,
      'evidence_score': 0.7,
      'num_sources': 3,
      'is_breaking': false,
      'is_developing': false,
      'headline_te': 'తెలంగాణ తాజా వార్త',
      'headline_en': 'Latest from Telangana',
      'body_te': 'ఇది వార్త వివరం.',
      'body_en': 'This is the story.',
    };

Future<AppState> _appState(
  WidgetTester tester,
  Future<http.Response> Function(http.Request) handler,
) async {
  SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_saved_test'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  final state = AppState(
    storage: _NoDiskStorage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      client: MockClient(handler),
    ),
  );
  await state.setLocale('te');
  return state;
}

class _NoDiskStorage extends Storage {
  _NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
}
