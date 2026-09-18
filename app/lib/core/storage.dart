import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Thin wrapper over [SharedPreferences] plus a small on-disk JSON cache.
///
/// The app is offline-tolerant: the last successfully fetched page is kept on
/// disk and shown when the network is unavailable, so a reader on a patchy
/// connection sees yesterday's news instead of a spinner.
class Storage {
  Storage(this._prefs, this._cacheDir);

  final SharedPreferences _prefs;
  final Directory _cacheDir;

  // -- preferences ----------------------------------------------------------

  String getString(String key, {String fallback = ''}) =>
      _prefs.getString(key) ?? fallback;

  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  /// The reader's chosen language, or Telugu when unset.
  String get locale => getString(localeKey, fallback: 'te');

  Future<bool> setLocale(String value) => setString(localeKey, value);

  String get themeMode => getString(themeModeKey, fallback: 'system');

  Future<bool> setThemeMode(String value) => setString(themeModeKey, value);

  bool get breakingAlerts => getBool(breakingAlertsKey, fallback: true);

  bool get dailyDigest => getBool(dailyDigestKey, fallback: false);

  String get homeSection => getString(homeSectionKey);

  String get homeDistrict => getString(homeDistrictKey);

  bool get onboardingDone => getBool(onboardingDoneKey);

  Future<bool> completeOnboarding() => setBool(onboardingDoneKey, true);

  // -- device identity ------------------------------------------------------

  /// A stable, locally generated reader id. This is not an advertising id; it
  /// is an opaque random string used only to keep bookmarks and reading
  /// history attached to this install, and the reader can reset it in Profile.
  String get deviceId {
    var id = getString(deviceIdKey);
    if (id.length < 8) {
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final salt = (DateTime.now().millisecond * 7919).toRadixString(36);
      id = 'dasha-$stamp-$salt';
      _prefs.setString(deviceIdKey, id);
    }
    return id;
  }

  Future<void> resetDeviceId() async {
    await _prefs.remove(deviceIdKey);
    await _prefs.remove(bookmarkCacheKey);
  }

  // -- feed cache -----------------------------------------------------------

  static const String bookmarkCacheKey = 'dasha.cache.bookmarks';

  File _cacheFile(String name) =>
      File('${_cacheDir.path}/dasha_cache_$name.json');

  /// Store a page of stories for offline reuse.
  Future<void> putCache(String name, String body) async {
    try {
      await _cacheFile(name).writeAsString(body);
    } on Exception {
      // Caching is a nicety, never a hard requirement.
    }
  }

  Future<String?> getCache(String name) async {
    try {
      final file = _cacheFile(name);
      if (!file.existsSync()) {
        return null;
      }
      final body = await file.readAsString();
      return body.isEmpty ? null : body;
    } on Exception {
      return null;
    }
  }

  Future<void> clearCache() async {
    for (final name in const ['feed', 'breaking', 'developing', 'search']) {
      try {
        final file = _cacheFile(name);
        if (file.existsSync()) {
          await file.delete();
        }
      } on Exception {
        // Cache cleanup must never block the reader.
      }
    }
  }
}
