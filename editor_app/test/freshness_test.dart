/// Tests for the elapsed-time labels the desk reads.
///
/// These are the difference between "this arrived five minutes ago, act on it"
/// and "we do not know when this arrived". The helper never invents an
/// interval, so every case here asserts either a real interval computed from
/// a fixed clock, or an honest fallback.
library;

import 'package:dasha_editor/core/freshness.dart';
import 'package:flutter_test/flutter_test.dart';

/// A clock held still so the intervals are exact, not flaky.
final DateTime _now = DateTime.utc(2026, 9, 20, 12, 0, 0);

String _iso(DateTime when) => when.toUtc().toIso8601String();

void main() {
  test('under a minute is just now, either side of the clock', () {
    expect(relativeTime(_iso(_now), now: _now), 'just now');
    expect(relativeTime(_iso(_now.subtract(const Duration(seconds: 30))),
        now: _now), 'just now');
    // Thirty seconds in the future is skew, not a story that has not happened.
    expect(relativeTime(_iso(_now.add(const Duration(seconds: 30))), now: _now),
        'just now');
  });

  test('minutes and hours count up in the singular and the plural', () {
    expect(
        relativeTime(_iso(_now.subtract(const Duration(minutes: 5))), now: _now),
        '5 minutes ago');
    expect(
        relativeTime(_iso(_now.subtract(const Duration(minutes: 1))), now: _now),
        '1 minute ago');
    expect(
        relativeTime(_iso(_now.subtract(const Duration(hours: 3))), now: _now),
        '3 hours ago');
    expect(
        relativeTime(_iso(_now.subtract(const Duration(hours: 1))), now: _now),
        '1 hour ago');
  });

  test('days count up to a week', () {
    expect(relativeTime(_iso(_now.subtract(const Duration(days: 2))), now: _now),
        '2 days ago');
  });

  test('beyond a week the date is more useful than a count', () {
    expect(
        relativeTime(_iso(_now.subtract(const Duration(days: 30))), now: _now),
        '21 Aug 2026');
  });

  test('a timestamp in the future is skew, not a fabricated interval', () {
    // An hour ahead is a clock that disagrees with ours by more than a minute;
    // the honest answer is the date, not "59 minutes ago".
    expect(relativeTime(_iso(_now.add(const Duration(hours: 1))), now: _now),
        '20 Sep 2026');
  });

  test('a missing timestamp is unknown, not "just now"', () {
    expect(relativeTime(null, now: _now), 'unknown time');
    expect(relativeTime('', now: _now), 'unknown time');
  });

  test('an unparseable timestamp is unknown rather than a crash', () {
    expect(relativeTime('not a timestamp', now: _now), 'unknown time');
  });

  test('a timestamp is read in the reader\'s local time', () {
    final local = _now.subtract(const Duration(minutes: 18)).toLocal();
    expect(relativeTime(local.toIso8601String(), now: _now),
        '18 minutes ago');
  });
}
