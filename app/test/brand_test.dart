import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/ui/pages/onboarding_page.dart';
import 'package:dasha_news/ui/pages/profile_page.dart';
import 'package:dasha_news/ui/pages/splash_page.dart';
import 'package:dasha_news/ui/router.dart';
import 'package:dasha_news/ui/widgets/masthead.dart';

/// The paper is `దశ న్యూస్`, and its mark is `దశ`. Three screens used to draw
/// `డ` instead — the first sound of the English transliteration, not of the
/// paper's own name. These tests pin the nameplate so it cannot slip back.
void main() {
  group('the nameplate', () {
    test('the constants the widgets draw are the paper’s own name', () {
      expect(teluguNameplate, 'దశ న్యూస్');
      expect(teluguMonogram, 'దశ');
      expect(latinNameplate, 'DASHA NEWS');
    });

    test('the monogram is the paper’s name, never the single డ glyph', () {
      // `డ` alone appears only inside legitimate Telugu words; the nameplate
      // and the monogram both carry `దశ`, so the stray mark is gone from the
      // brand widgets by construction.
      expect(teluguMonogram, isNot('డ'));
      expect(teluguNameplate.startsWith('దశ'), isTrue);
    });

    testWidgets('the splash screen shows the masthead lockup', (tester) async {
      await _fakePlugins(tester);
      final app = await _appState(tester);
      await tester.pumpWidget(_root(app, const SplashPage()));

      // The first frame carries the splash-sized lockup before the splash
      // routes away to onboarding or home.
      await tester.pump();
      expect(
        find.byWidgetPredicate(
            (widget) => widget is DashaMasthead && widget.size == MastheadSize.splash),
        findsOneWidget,
      );
      expect(find.text(teluguNameplate), findsOneWidget);
      expect(find.text(latinNameplate), findsOneWidget);
    });

    testWidgets('onboarding carries the monogram', (tester) async {
      await _fakePlugins(tester);
      final app = await _appState(tester);
      await tester.pumpWidget(_root(app, const OnboardingPage()));
      await tester.pump();

      expect(find.byType(DashaMonogram), findsOneWidget);
      expect(find.text(teluguMonogram), findsOneWidget);
    });

    testWidgets('the About card carries the monogram beside the app name',
        (tester) async {
      await _fakePlugins(tester);
      final app = await _appState(tester);
      await tester.pumpWidget(_root(app, const ProfilePage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The About card is below the fold of the settings list.
      await tester.scrollUntilVisible(
        find.byType(DashaMonogram),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(DashaMonogram), findsOneWidget);
      expect(find.text(app.strings.appName), findsWidgets);
    });
  });
}

/// Stands in for the plugins these three screens reach for but the headless
/// tester does not have: connectivity (listened in [AppState.init]) and
/// package info (read by the About card).
Future<void> _fakePlugins(WidgetTester tester) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  const connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const connectivityEvents =
      MethodChannel('dev.fluttercommunity.plus/connectivity_status');
  const packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

  messenger.setMockMethodCallHandler(connectivity,
      (call) async => <String>['wifi']);
  messenger.setMockMethodCallHandler(connectivityEvents, (call) async => null);
  messenger.setMockMethodCallHandler(packageInfo, (call) async => <String, dynamic>{
        'appName': 'Dasha News',
        'packageName': 'news.dasha.app',
        'version': '0.1.0',
        'buildNumber': '1',
        'buildSignature': '',
      });

  addTearDown(() {
    messenger.setMockMethodCallHandler(connectivity, null);
    messenger.setMockMethodCallHandler(connectivityEvents, null);
    messenger.setMockMethodCallHandler(packageInfo, null);
  });
}

Widget _root(AppState app, Widget home) {
  return ChangeNotifierProvider<AppState>.value(
    value: app,
    child: MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: DashaRouter.onGenerateRoute,
      home: home,
    ),
  );
}

Future<AppState> _appState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({localeKey: 'te'});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_brand_cache'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  return AppState(
    storage: Storage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      // The newsroom is unreachable here; raising the app's own offline error
      // keeps any page that fetches on the happy path of its error handling.
      client: MockClient((_) async => throw ApiException.offline()),
    ),
  );
}
