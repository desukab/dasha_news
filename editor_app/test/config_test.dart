import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_editor/core/config.dart';

/// Where the desk's app looks for its newsroom.
///
/// The defect this guards against is `10.0.2.2` as the shipped default: that
/// alias resolves to the host only inside an Android emulator, so a release
/// built on it opened to a login screen that could never be answered. The
/// address is now a build fact (`--dart-define=DASHA_API_BASE`) and the alias
/// is a debug-only fallback.
void main() {
  group('defaultBaseUrl', () {
    test('a test build points at the emulator alias, which is debug-only', () {
      expect(isReleaseBuild, isFalse);
      expect(defaultBaseUrl, 'http://10.0.2.2:8000');
    });

    test('the release fallback is an explicit placeholder, never the alias', () {
      expect(isUnresolved(unresolvedBaseUrl), isTrue);
      expect(isUnresolved('http://10.0.2.2:8000'), isFalse);
      expect(unresolvedBaseUrl, isNot(equals('http://10.0.2.2:8000')));
    });
  });
}
