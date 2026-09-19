import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/state/app_state.dart';

/// Where the app looks for its newsroom.
///
/// The defect this guards against is `10.0.2.2` as the shipped default: that
/// alias resolves to the host only inside an Android emulator, so a release
/// built on it had no backend at all. The address is now a build fact
/// (`--dart-define=DASHA_API_BASE`) that a reader preference still overrides,
/// and a release with no define lands on an explicit placeholder rather than
/// on an address no phone can route to.
void main() {
  group('defaultBaseUrl', () {
    test('a test build points at the emulator alias, which is debug-only', () {
      // `dart.vm.product` is false under `flutter test`, and no
      // DASHA_API_BASE define is passed, so this is the debug path: a
      // developer's emulator reaching a newsroom on their own machine.
      expect(isReleaseBuild, isFalse);
      expect(defaultBaseUrl, 'http://10.0.2.2:8000');
    });

    test('the release fallback is an explicit placeholder, never the alias', () {
      // The alias can only be chosen when [isReleaseBuild] is false; the
      // release branch is a compile-time one, so what can be asserted here is
      // that the two are mutually exclusive and that the placeholder is what
      // a release with no define resolves to.
      expect(isUnresolved(unresolvedBaseUrl), isTrue);
      expect(isUnresolved('http://10.0.2.2:8000'), isFalse);
      expect(unresolvedBaseUrl, isNot(equals('http://10.0.2.2:8000')));
    });
  });

  // SharedPreferences caches one instance per process, so mock initial values
  // are only honoured by the first [SharedPreferences.getInstance]. Each test
  // therefore writes its own starting state through that instance instead of
  // trying to install a second one.
  group('resolution order', () {
    test('a reader override beats the build default', () async {
      final storage = await _storage();
      await storage.setString(baseUrlKey, 'https://my.newsroom.example');
      // The client below is built on a placeholder, so a resolution that
      // copied the client instead of reading storage shows up here.
      expect(_app(storage).baseUrl, 'https://my.newsroom.example');
    });

    test('nothing stored falls back to the build default', () async {
      final storage = await _storage();
      expect(_app(storage).baseUrl, defaultBaseUrl);
    });

    test('an empty stored value falls back too', () async {
      final storage = await _storage();
      await storage.setString(baseUrlKey, '');
      expect(_app(storage).baseUrl, defaultBaseUrl);
    });
  });

  group('setBaseUrl', () {
    test('accepts an http address and points the client at it', () async {
      final storage = await _storage();
      final app = _app(storage);
      expect(await app.setBaseUrl('http://192.168.1.5:8000'), isTrue);
      expect(app.baseUrl, 'http://192.168.1.5:8000');
      expect(app.api.baseUrl, 'http://192.168.1.5:8000');
      expect(storage.getString(baseUrlKey), 'http://192.168.1.5:8000');
    });

    test('rejects an empty value', () async {
      final app = _app(await _storage());
      expect(await app.setBaseUrl('   '), isFalse);
      expect(app.baseUrl, defaultBaseUrl);
    });

    test('rejects a value without a scheme', () async {
      final app = _app(await _storage());
      expect(await app.setBaseUrl('news.dasha.example'), isFalse);
      expect(await app.setBaseUrl('ftp://news.dasha.example'), isFalse);
    });
  });
}

/// Fresh storage on a freshly-cleared preferences store, so no test inherits
/// the override another wrote.
Future<Storage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final cache = await Directory.systemTemp.createTemp('dasha_config_cache');
  addTearDown(() => cache.delete(recursive: true));
  return Storage(prefs, cache);
}

/// The client never talks to anything: these tests are about where the address
/// comes from, not whether it answers.
AppState _app(Storage storage) {
  return AppState(
    storage: storage,
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      client: MockClient((_) async => throw ApiException.offline()),
    ),
  );
}
