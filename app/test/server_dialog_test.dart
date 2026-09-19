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
import 'package:dasha_news/ui/pages/profile_page.dart';

/// The server setting is the one place a reader can point the app at a
/// different newsroom, so it has to say plainly when what they typed did not
/// take. Silently keeping the old address looks like a save that worked.
void main() {
  testWidgets('an address with no scheme is refused out loud', (tester) async {
    final app = await _appState(tester);
    await _pump(tester, app);
    await tester.pumpAndSettle();

    // Nothing stored, and a test build is not a product build, so this is the
    // debug default the emulator uses to reach the host's own loopback.
    expect(app.baseUrl, defaultBaseUrl);

    final strings = AppStrings(app.locale);
    await _editServer(tester, strings, 'news.dasha.example');
    await tester.pumpAndSettle();

    // The dialog is still open, complaining, and nothing was saved.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(strings.serverInvalid), findsOneWidget);
    expect(app.baseUrl, defaultBaseUrl);
  });

  testWidgets('a scheme-bearing address is saved and the dialog closes',
      (tester) async {
    final app = await _appState(tester);
    await _pump(tester, app);
    await tester.pumpAndSettle();

    await _editServer(tester, AppStrings(app.locale), 'https://news.dasha.example');
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(app.baseUrl, 'https://news.dasha.example');
    expect(
      app.storage.getString(baseUrlKey),
      'https://news.dasha.example',
    );
  });
}

Future<void> _editServer(
  WidgetTester tester,
  AppStrings strings,
  String value,
) async {
  // The tile sits below the fold of the settings list, so it is brought into
  // view before it can be tapped.
  await tester.ensureVisible(find.text(strings.server));
  await tester.tap(find.text(strings.server));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), value);
  await tester.pump();
  await tester.tap(find.text(strings.save));
  await tester.pump();
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
        home: const ProfilePage(),
      ),
    ),
  );
}

Future<AppState> _appState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_server_test'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  return AppState(
    storage: _NoDiskStorage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      // setBaseUrl pokes /v1/health to see whether the new origin answers.
      client: MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 200,
            headers: const {'content-type': 'application/json'});
      }),
    ),
  );
}

class _NoDiskStorage extends Storage {
  _NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
}
