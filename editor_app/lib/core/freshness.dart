/// How long ago a thing happened, in the words the desk reads it in.
///
/// Never invents a timestamp. A missing or unparseable time is reported as
/// unknown rather than coerced into "just now", because the difference between
/// "five minutes ago" and "we do not know when this arrived" is the difference
/// between acting on a tip and sitting on one. A timestamp in the future is a
/// clock that disagrees with ours, not a story that has not happened yet, so
/// beyond a minute of skew it falls back to the date instead of to a made-up
/// elapsed interval.
library;

/// `now` is a parameter rather than `DateTime.now()` so a test can hold time
/// still; the desk gets wall-clock time.
String relativeTime(String? iso, {DateTime? now}) {
  final when = _parse(iso);
  if (when == null) return 'unknown time';
  final delta = (now ?? DateTime.now()).difference(when);
  if (delta.inSeconds.abs() < 60) return 'just now';
  if (delta.isNegative) return _shortDate(when);
  if (delta.inMinutes < 60) {
    final m = delta.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (delta.inHours < 24) {
    final h = delta.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  if (delta.inDays < 7) {
    final d = delta.inDays;
    return '$d day${d == 1 ? '' : 's'} ago';
  }
  return _shortDate(when);
}

DateTime? _parse(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toLocal();
}

String _shortDate(DateTime when) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}
