library;

/// Small presentation helpers.
///
/// Times are rendered relative to now, because "two hours ago" is what a
/// reader actually wants from a news app; the absolute timestamp is still
/// available on the story page.
import 'package:intl/intl.dart';

import 'app_strings.dart';

/// Formats [when] with [pattern] in the Indian English locale.
///
/// intl throws [LocaleDataException] for an explicit locale whose symbol data
/// has not been loaded by `initializeDateFormatting`. That used to take the
/// whole front page down, because the throw landed inside the list builder and
/// a release build renders the failed item as a blank ErrorWidget. A date is
/// never worth that, so a formatting failure degrades to a plain date instead.
String formatIndianDate(String pattern, DateTime when) {
  try {
    return DateFormat(pattern, 'en_IN').format(when);
  } catch (_) {
    return '${when.day} ${when.month} ${when.year}';
  }
}

String relativeTime(DateTime? when, {DateTime? now, AppStrings? strings}) {
  if (when == null) {
    return '';
  }
  final s = strings ?? const AppStrings('te');
  final reference = now ?? DateTime.now();
  final delta = reference.difference(when);
  if (delta.isNegative || delta.inSeconds < 45) {
    return s.justNow;
  }
  if (delta.inMinutes < 60) {
    return '${delta.inMinutes} ${s.minutesAgo}';
  }
  if (delta.inHours < 24) {
    return '${delta.inHours} ${s.hoursAgo}';
  }
  if (delta.inDays < 7) {
    return '${delta.inDays} ${s.daysAgo}';
  }
  return formatIndianDate('d MMM y', when.toLocal());
}

/// Absolute timestamp for the story page, where a reader may need to quote it.
String absoluteTime(DateTime? when) {
  if (when == null) {
    return '';
  }
  return formatIndianDate('d MMMM y, h:mm a', when.toLocal());
}

/// A rough reading-time estimate. Telugu is read more slowly per glyph than
/// English, so the constant is set for Telugu and is merely conservative for
/// the other two languages.
String readingTime(String? body) {
  final words = (body ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  final minutes = (words / 140).ceil();
  return minutes < 1 ? '1' : '$minutes';
}

/// Large counts are compressed the way Indian news fronts do.
String compactCount(int value) {
  if (value < 1000) {
    return '$value';
  }
  if (value < 100000) {
    final thousands = value / 1000;
    return thousands == thousands.roundToDouble()
        ? '${thousands.round()}k'
        : '${thousands.toStringAsFixed(1)}k';
  }
  final lakhs = value / 100000;
  return lakhs == lakhs.roundToDouble()
      ? '${lakhs.round()}L'
      : '${lakhs.toStringAsFixed(1)}L';
}

/// True when a string contains Telugu script. Used to pick a script-aware
/// line height without sniffing the current language setting.
bool hasTeluguScript(String? text) {
  if (text == null || text.isEmpty) {
    return false;
  }
  for (final code in text.runes) {
    if (code >= 0x0C00 && code <= 0x0C7F) {
      return true;
    }
  }
  return false;
}

/// "శుక్రవారం, 19 సెప్టెంబరు" in Telugu, or the English long form: the edition
/// line a front page carries under its name.
///
/// Formatted off the English names and translated here rather than handed to
/// `intl` with a Telugu locale, because Telugu locale data is not loaded
/// unless the app initialises it explicitly. [formatIndianDate] carries the
/// same reasoning one step further: even the English data failing to load
/// yields a plain date rather than no front page at all.
String editionDateLine(AppStrings strings, {DateTime? when}) {
  final english =
      formatIndianDate('EEEE, d MMMM y', when ?? DateTime.now()).split(', ');
  final weekday = english.first;
  final rest = english.last.split(' ');
  if (strings.code != 'te') return english.join(', ');
  // The fallback path in [formatIndianDate] — intl failing to load — yields
  // 'd M y' with no month name to translate, in which case the day and year
  // are still right and only the weekday lookup is pointless.
  if (rest.length < 3) return english.join(', ');
  final teWeekday = _teWeekdays[weekday] ?? weekday;
  final teMonth = _teMonths[rest[1]] ?? rest[1];
  return '$teWeekday, ${rest[0]} $teMonth ${rest[2]}';
}

/// Telugu weekday names, keyed off the English `intl` produces.
const Map<String, String> _teWeekdays = {
  'Monday': 'సోమవారం',
  'Tuesday': 'మంగళవారం',
  'Wednesday': 'బుధవారం',
  'Thursday': 'గురువారం',
  'Friday': 'శుక్రవారం',
  'Saturday': 'శనివారం',
  'Sunday': 'ఆదివారం',
};

/// Telugu month names, in the same keying scheme.
const Map<String, String> _teMonths = {
  'January': 'జనవరి',
  'February': 'ఫిబ్రవరి',
  'March': 'మార్చి',
  'April': 'ఏప్రిల్',
  'May': 'మే',
  'June': 'జూన్',
  'July': 'జూలై',
  'August': 'ఆగస్టు',
  'September': 'సెప్టెంబరు',
  'October': 'అక్టోబరు',
  'November': 'నవంబరు',
  'December': 'డిసెంబరు',
};
