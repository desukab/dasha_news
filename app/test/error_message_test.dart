import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/core/error_message.dart';

/// The transport layer speaks English to itself; the reader's screen is not
/// the place it says so. A newsroom that cannot be reached is reported in the
/// reader's own language, and the raw message stays in the log.
void main() {
  const strings = AppStrings('en');

  group('an unreachable newsroom is said in the reader language', () {
    test('an offline failure does not leak the transport message', () {
      final error = ApiException.offline('the request could not be sent');
      expect(errorMessage(strings, error), strings.errorOffline);
      expect(errorMessage(strings, error), isNot(contains('request')));
    });

    test('a timeout is the same failure the reader can act on', () {
      expect(
        errorMessage(strings, ApiException.timeout()),
        strings.errorOffline,
      );
    });

    test('a network failure is not shown as a raw socket string', () {
      final error = ApiException.network(
        'Failed host lookup: news.dasha.example',
      );
      expect(errorMessage(strings, error), strings.errorOffline);
      expect(errorMessage(strings, error), isNot(contains('host lookup')));
    });
  });

  group('a failure the reader cannot act on stays generic', () {
    test('a server error is the generic message', () {
      expect(
        errorMessage(strings, const ApiException(500, 'internal')),
        strings.errorGeneric,
      );
    });

    test('a missing story is the generic message too', () {
      expect(
        errorMessage(strings, const ApiException(404, 'not found')),
        strings.errorGeneric,
      );
    });
  });

  test('no error at all is still a sentence, not a blank', () {
    expect(errorMessage(strings, null), strings.errorGeneric);
  });

  // The three languages the paper prints in. A string present in one and
  // missing in another is a defect, so all three are asserted here.
  for (final code in const ['te', 'ten', 'en']) {
    test('the $code offline message is present and non-empty', () {
      final lang = AppStrings(code);
      expect(lang.errorOffline, isNotEmpty);
      expect(lang.errorGeneric, isNotEmpty);
    });
  }
}
