import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/app_strings.dart';

/// A string present in one language and missing in another is a defect the
/// reader sees, so this asserts every language carries every key. It also
/// guards the specific ones the UI used to hard-code in English.
void main() {
  const codes = ['te', 'ten', 'en'];

  group('every language carries every key the UI looks up', () {
    for (final code in codes) {
      final strings = AppStrings(code);
      final values = <String, String>{
        'online': strings.online,
        'offline': strings.offline,
        'offlineHint': strings.offlineHint,
        'errorGeneric': strings.errorGeneric,
        'errorOffline': strings.errorOffline,
        'ok': strings.ok,
        'cancel': strings.cancel,
        'notFound': strings.notFound,
        'retry': strings.retry,
        'appName': strings.appName,
      };
      for (final entry in values.entries) {
        test('$code.${entry.key} is present and non-empty', () {
          expect(entry.value, isNotEmpty);
        });
      }
    }
  });

  group('the strings that used to be hard-coded English', () {
    test('Telugu has its own word for online', () {
      expect(AppStrings('te').online, 'ఆన్‌లైన్');
      expect(AppStrings('en').online, isNot(equals('ఆన్‌లైన్')));
    });

    test('the 404 page is not English-only', () {
      expect(AppStrings('te').notFound, isNot('Page not found'));
      expect(AppStrings('en').notFound, 'Page not found');
    });
  });
}
