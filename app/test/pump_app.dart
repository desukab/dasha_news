import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/core/theme.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/state/audio_controller.dart';
import 'package:dasha_news/state/feed_repository.dart';
import 'package:dasha_news/state/history_recorder.dart';
import 'package:dasha_news/ui/pages/home_page.dart';

/// The harness every stream test shares: the providers the app's widgets read,
/// mounted the way `main()` mounts them.
///
/// The provider list, the AudioController's ownership, and the settle the
/// cache-first bootstrap needs before a screen is drawn are all one thing that
/// happens to be written in five places otherwise. A fourth provider would
/// then be five edits with five chances to miss one.

/// The cache write is real `dart:io` I/O, which never completes inside a widget
/// test's fake-async zone on this host. Stubbing it keeps a test on the render
/// path, which is what the test is for.
class NoDiskStorage extends Storage {
  NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
}

/// A cache that already holds a previous run's front page, which is what a cold
/// start that cannot reach the newsroom finds on the reader's phone.
class SeededStorage extends NoDiskStorage {
  SeededStorage(super.prefs, super.cache, this.front);

  final String front;

  @override
  Future<String?> getCache(String name) async =>
      name == CacheNames.front ? front : null;
}

/// A temp directory that is removed when the test ends. Real `dart:io` I/O, so
/// the caller must already be inside [WidgetTester.runAsync].
Future<Directory> testCacheDir(WidgetTester tester, String prefix) async {
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp(prefix),
  ))!;
  addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
  return dir;
}

/// The reader's onboarding is already done, so the stream is where they land.
Future<SharedPreferences> onboardedPrefs() async {
  SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
  return SharedPreferences.getInstance();
}

/// One screen forward, the way the reader gets there: a drag one page tall,
/// then a full settle.
///
/// The drag spans a whole page rather than a fixed offset, so the snap lands
/// one screen forward under any surface size rather than because the default
/// test surface happens to be 800×600. The settle is `pumpAndSettle` rather
/// than a fixed wait, so a page caught mid-flight at sample time becomes
/// impossible rather than unlikely. That is safe on a loaded stream because
/// the only perpetual animation in the app is the loading skeleton, which the
/// front page discards the moment the newsroom answers — if a shimmer or a
/// pulsing badge ever lands on the stream, this hangs to the timeout instead
/// of failing fast, and this comment is where to look.
Future<void> swipeNext(WidgetTester tester) async {
  final page = find.byType(PageView);
  final height = tester.getSize(page).height;
  await tester.drag(page, Offset(0, -height));
  await tester.pumpAndSettle();
}

/// Pumps the stream: the three providers, the AudioController constructed
/// eagerly and owned by this test because a provider built with `.value` does
/// not dispose its notifier, and the settle the bootstrap needs.
Future<void> pumpStream(WidgetTester tester, AppState app) async {
  // Constructed eagerly and passed by value, the way `main()` wires it. A
  // provider created lazily is not disposed by the tree either, and a cold
  // start that has to load first leaves it unset at pump time — so the eager
  // construction is what makes the disposal reliable.
  final audio = AudioController(app);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<AudioController>.value(value: audio),
        Provider<HistoryRecorder>(create: (_) => HistoryRecorder(app)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const HomePage(),
      ),
    ),
  );
  addTearDown(audio.dispose);

  await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
