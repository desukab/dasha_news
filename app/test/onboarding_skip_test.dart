import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/ui/pages/home_page.dart';
import 'package:dasha_news/ui/pages/onboarding_page.dart';
import 'package:dasha_news/ui/router.dart';

/// Onboarding Skip is the gate between the reader and the paper, and it used
/// to wait on the network: `_finish()` awaited `syncDevice()` — a POST with a
/// 50-second timeout — before navigating, so a first run on a cold or offline
/// phone appeared dead for up to a minute while the flag was already written.
///
/// The fix is that onboarding is a local fact. This test pins it: with a
/// newsroom that holds every POST open, Skip still persists and lands the
/// reader on Home while the device sync is still in flight.
void main() {
  testWidgets('Skip persists onboarding and reaches Home without the network',
      (tester) async {
    await _fakeConnectivity(tester);
    final newsroom = _HeldNewsroom();
    final app = await _appState(tester, newsroom);
    await tester.runAsync(() => app.init());

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          onGenerateRoute: DashaRouter.onGenerateRoute,
          home: const OnboardingPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(app.strings.skip), findsOneWidget);
    await tester.tap(find.text(app.strings.skip));
    // Storage and the route push are real I/O; give them a few pumps rather
    // than a settle, because the front page's skeleton animation never ends.
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(HomePage), findsOneWidget);
    expect(app.storage.onboardingDone, isTrue);
    // The POST the old code blocked on is still open — that is the point: the
    // reader is already reading while the newsroom has not answered.
    expect(newsroom.posts, isNotEmpty);

    // Release the held requests so nothing outlives the test.
    newsroom.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('finishing the flow lands on Home', (tester) async {
    await _fakeConnectivity(tester);
    final newsroom = _HeldNewsroom();
    final app = await _appState(tester, newsroom);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          onGenerateRoute: DashaRouter.onGenerateRoute,
          home: const OnboardingPage(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(app.strings.next));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(app.strings.next));
    await tester.pump(const Duration(milliseconds: 300));
    // The summary step's heading uses the same string as the CTA, so tap the
    // button itself rather than the text.
    await tester.tap(find.widgetWithText(FilledButton, app.strings.getStarted));
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.byType(HomePage), findsOneWidget);

    newsroom.release();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

/// A newsroom that answers every read with the app's own offline error and
/// holds every POST open until the test releases it.
///
/// Holding the POST is what makes this test catch the bug rather than pass it:
/// the old code awaited [AppState.syncDevice] before navigating, so against a
/// newsroom that never answers the reader never reached Home.
class _HeldNewsroom {
  final Completer<void> _gate = Completer<void>();
  final List<Uri> posts = [];

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

/// Stands in for the native connectivity plugin, which is not present in the
/// headless tester; without it [AppState.init]'s subscription errors.
Future<void> _fakeConnectivity(WidgetTester tester) async {
  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const events = MethodChannel('dev.fluttercommunity.plus/connectivity_status');
  final messenger = tester.binding.defaultBinaryMessenger;

  messenger.setMockMethodCallHandler(channel,
      (MethodCall call) async => <String>['wifi']);
  messenger.setMockMethodCallHandler(events, (MethodCall call) async => null);

  addTearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });
}

/// An [AppState] whose newsroom never finishes a POST, which is what a first
/// run with no signal looks like.
Future<AppState> _appState(WidgetTester tester, _HeldNewsroom newsroom) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_onboarding_cache'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  return AppState(
    storage: Storage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      client: MockClient((request) async {
        if (request.method == 'POST') {
          newsroom.posts.add(request.url);
          await newsroom._gate.future;
        }
        throw ApiException.offline();
      }),
    ),
  );
}
