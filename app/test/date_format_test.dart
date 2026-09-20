import 'package:dasha_news/core/format.dart';
import 'package:dasha_news/core/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

/// The front page used to render blank in release builds. `main()` never loaded
/// intl's locale data, so `DateFormat(..., 'en_IN')` threw `LocaleDataException`
/// inside the list's item builder, where a release build swallows the failure
/// into a blank ErrorWidget. These tests pin both halves of the fix: the data
/// main() loads is enough, and the helpers degrade instead of throwing even if
/// it is not.
void main() {
  test('main initialises the locale data the front page formats with', () async {
    // Exactly what main() does, before the first frame.
    await initializeDateFormatting('en_IN');

    expect(
      DateFormat('EEEE, d MMMM y', 'en_IN').format(DateTime(2026, 9, 19)),
      'Saturday, 19 September 2026',
    );
  });

  test('the masthead date line formats in both languages', () {
    // Pinned to a fixed date: the line is derived from DateTime.now(), and a
    // test that asserts one weekday while reading today's breaks every time
    // the calendar moves off it.
    final when = DateTime(2026, 9, 19);
    final line = editionDateLine(const AppStrings('te'), when: when);
    expect(line, isNotEmpty);
    // Saturday in Telugu, unmangled by the formatter.
    expect(line, contains('శనివారం'));

    final english = editionDateLine(const AppStrings('en'), when: when);
    expect(english, contains('Saturday'));
  });

  test('a date older than a week reaches the DateFormat branch', () {
    final old = DateTime.now().subtract(const Duration(days: 30));
    // relativeTime only formats when the relative buckets run out.
    expect(() => relativeTime(old), returnsNormally);
    expect(relativeTime(old), isNotEmpty);
  });

  test('the story page timestamp never throws', () {
    expect(() => absoluteTime(DateTime(2025, 3, 4, 14, 30)), returnsNormally);
    expect(absoluteTime(DateTime(2025, 3, 4, 14, 30)), isNotEmpty);
  });
}
