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
import 'package:dasha_news/ui/pages/story_detail_page.dart';
import 'package:dasha_news/ui/router.dart';
import 'package:dasha_news/widgets/states_view.dart';

/// The story page reached from a deep link has no story object yet, so it is
/// fetched on arrival. That fetch is allowed to fail — and when it does the
/// reader has to be told, not shown an empty article with the bookmark and
/// share buttons still dangling under it.
void main() {
  testWidgets('a story the newsroom could not reach says so', (tester) async {
    final app = await _appState(tester, (request) async {
      // The reader opened a shared link on a train: the newsroom is
      // unreachable and there is no cached story to fall back on.
      throw const SocketException('no network in tests');
    });

    await _pump(tester, app, const StoryDetailArgs(id: 77));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final strings = AppStrings(app.locale);
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text(strings.offline), findsOneWidget);
    expect(find.text(strings.offlineHint), findsOneWidget);
    expect(find.text(strings.retry), findsOneWidget);
    // The action buttons belong to a story that loaded.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('a story that loaded draws it, not the error state',
      (tester) async {
    final app = await _appState(tester, (request) async {
      return http.Response(jsonEncode(_storyJson(77)), 200,
          headers: const {'content-type': 'application/json'});
    });

    await _pump(tester, app, const StoryDetailArgs(id: 77));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(ErrorState), findsNothing);
    expect(find.text('తెలంగాణ తాజా వార్త'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNWidgets(2));
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppState app,
  StoryDetailArgs args,
) async {
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
        home: StoryDetailPage(args: args),
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
    () => Directory.systemTemp.createTemp('dasha_story_test'),
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
