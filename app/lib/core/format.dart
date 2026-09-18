library;

/// Small presentation helpers.
///
/// Times are rendered relative to now, because "two hours ago" is what a
/// reader actually wants from a news app; the absolute timestamp is still
/// available on the story page.
import 'package:intl/intl.dart';

import 'app_strings.dart';

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
  return DateFormat('d MMM y', 'en_IN').format(when.toLocal());
}

/// Absolute timestamp for the story page, where a reader may need to quote it.
String absoluteTime(DateTime? when) {
  if (when == null) {
    return '';
  }
  return DateFormat('d MMMM y, h:mm a', 'en_IN').format(when.toLocal());
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
