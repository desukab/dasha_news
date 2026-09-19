import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/widgets/states_view.dart';

/// An error screen is the worst possible place to switch scripts on someone.
/// ErrorState used to look its strings up in a fixed 'te' locale, so an
/// English reader who lost the newsroom was told so in Telugu.
void main() {
  for (final code in const ['en', 'ten', 'te']) {
    testWidgets('the error state speaks the $code reader\'s language',
        (tester) async {
      final app = await _appState(tester, locale: code);
      await _pump(tester, app);
      final strings = AppStrings(code);

      // The title and the retry button come from the reader's own table, not
      // a fixed one.
      expect(find.text(strings.errorGeneric), findsOneWidget);
      expect(find.text(strings.retry), findsOneWidget);
      // The message the caller passed is still drawn, so nothing is hidden.
      expect(find.text('untranslated'), findsOneWidget);
    });
  }

  testWidgets('an offline error is labelled offline, not generic',
      (tester) async {
    final app = await _appState(tester, locale: 'en');
    await _pump(tester, app, offlineHint: true);
    const strings = AppStrings('en');

    expect(find.text(strings.offline), findsOneWidget);
    expect(find.text(strings.offlineHint), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppState app, {
  bool offlineHint = false,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ErrorState(
            message: 'untranslated',
            onRetry: () {},
            offlineHint: offlineHint,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A real [AppState] wired to an unreachable newsroom, hydrated with the
/// locale under test. The temp cache directory is created under
/// [WidgetTester.runAsync] because a widget test runs in a fake-async zone and
/// real `dart:io` I/O scheduled there never completes on this host.
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
  await state.setLocale(locale);
  return state;
}
