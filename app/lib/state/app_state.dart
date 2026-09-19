import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/app_strings.dart';
import '../core/config.dart';
import '../core/storage.dart';
import '../models/page.dart';

/// Global, long-lived application state: the reader's identity, language,
/// theme, the section/district catalogues, and the bookmark set.
///
/// Everything here survives a route change and is shared by every screen.
/// List paging lives in [PagedList], one instance per screen.
class AppState extends ChangeNotifier {
  AppState({required this.storage, ApiClient? api})
      : _api = api ?? ApiClient(baseUrl: _resolveBaseUrl(storage)) {
    // Resolved here rather than only in [init] because `baseUrl` is read
    // before init finishes — the splash routes on it. init() re-resolves it
    // too; the two agree unless storage changed in between.
    _baseUrl = _resolveBaseUrl(storage);
  }

  /// The newsroom origin this install actually talks to.
  ///
  /// A URL the reader set in Profile → Server always wins, because that is the
  /// reader telling the app where their newsroom is. Otherwise the build's own
  /// default is used — a `--dart-define` value in a release build, or the
  /// emulator's host alias in a debug one. Nothing here is `10.0.2.2` unless
  /// the build is a debug build with no define.
  static String _resolveBaseUrl(Storage storage) {
    final stored = storage.getString(baseUrlKey);
    if (stored.isNotEmpty) return stored;
    final built = defaultBaseUrl;
    return built.isEmpty ? unresolvedBaseUrl : built;
  }

  final Storage storage;
  final ApiClient _api;

  late String _baseUrl;
  String _locale = 'te';
  String _themeMode = 'system';
  bool _breakingAlerts = true;
  bool _dailyDigest = false;
  bool _online = true;
  bool _initialised = false;

  final List<NewsSection> _sections = [];
  final List<String> _districts = [];
  final Set<int> _bookmarked = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivity;

  ApiClient get api => _api;

  String get baseUrl => _baseUrl;

  String get locale => _locale;

  String get themeMode => _themeMode;

  bool get breakingAlerts => _breakingAlerts;

  bool get dailyDigest => _dailyDigest;

  bool get online => _online;

  bool get initialised => _initialised;

  List<NewsSection> get sections => List.unmodifiable(_sections);

  List<String> get districts => List.unmodifiable(_districts);

  bool isBookmarked(int storyId) => _bookmarked.contains(storyId);

  AppStrings get strings => AppStrings(locale);

  ThemeMode get themeModeValue {
    switch (_themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  /// Loads persisted preferences and the server catalogues.
  ///
  /// Catalogue failures are never fatal: the app can render a feed without
  /// knowing the full section list, so a dead /v1/sections must not block
  /// startup.
  Future<void> init() async {
    if (_initialised) return;
    _baseUrl = _resolveBaseUrl(storage);
    _api.baseUrl = _baseUrl;
    _locale = storage.locale;
    _themeMode = storage.themeMode;
    _breakingAlerts = storage.breakingAlerts;
    _dailyDigest = storage.dailyDigest;
    await _refreshBookmarks();
    _initialised = true;
    notifyListeners();

    _connectivity = Connectivity().onConnectivityChanged.listen((result) {
      final online = !result.contains(ConnectivityResult.none);
      if (online != _online) {
        _online = online;
        notifyListeners();
      }
    });

    unawaited(refreshCatalogues());
    unawaited(syncDevice());
  }

  @override
  void dispose() {
    _connectivity?.cancel();
    super.dispose();
  }

  /// Re-fetches the section and district lists, writing each to the cache.
  Future<void> refreshCatalogues({bool fromCacheFirst = true}) async {
    if (fromCacheFirst && _sections.isEmpty) {
      await _loadCataloguesFromCache();
    }
    try {
      final catalogue = await _api.sections();
      _sections
        ..clear()
        ..addAll(catalogue.all);
      await storage.putCache('sections', jsonEncode(catalogue.all
          .map((s) => {
                'slug': s.slug,
                'te': s.te,
                'ten': s.ten,
                'en': s.en,
                'sensitive': s.sensitive,
                'telangana_local': s.telanganaLocal,
              })
          .toList()));
    } on ApiException {
      // Keep whatever we have; a stale taxonomy is better than none.
    }
    try {
      final list = await _api.districts();
      if (list.isNotEmpty) {
        _districts
          ..clear()
          ..addAll(list);
      }
    } on ApiException {
      // ignore
    }
    notifyListeners();
  }

  Future<void> _loadCataloguesFromCache() async {
    final cached = await storage.getCache('sections');
    if (cached == null) return;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is List) {
        _sections.clear();
        for (final entry in decoded) {
          if (entry is Map<String, dynamic>) {
            _sections.add(NewsSection.fromJson(entry));
          }
        }
      }
    } on Exception {
      // A corrupt cache is discarded, not shown.
    }
  }

  /// The reader's language, persisted and pushed to the newsroom so it can
  /// return the right script for every headline.
  Future<void> setLocale(String value) async {
    if (_locale == value) return;
    _locale = value;
    await storage.setLocale(value);
    notifyListeners();
    unawaited(syncDevice());
  }

  Future<void> setThemeMode(String value) async {
    if (_themeMode == value) return;
    _themeMode = value;
    await storage.setThemeMode(value);
    notifyListeners();
    unawaited(syncDevice());
  }

  Future<void> setBreakingAlerts(bool value) async {
    if (_breakingAlerts == value) return;
    _breakingAlerts = value;
    await storage.setBool(breakingAlertsKey, value);
    notifyListeners();
    unawaited(syncDevice());
  }

  Future<void> setDailyDigest(bool value) async {
    if (_dailyDigest == value) return;
    _dailyDigest = value;
    await storage.setBool(dailyDigestKey, value);
    notifyListeners();
    unawaited(syncDevice());
  }

  /// Points the app at a different newsroom. Used for testing and for
  /// readers who host their own instance.
  Future<bool> setBaseUrl(String value) async {
    final candidate = value.trim();
    if (candidate.isEmpty) return false;
    if (!candidate.startsWith('http://') && !candidate.startsWith('https://')) {
      return false;
    }
    _baseUrl = candidate;
    await storage.setString(baseUrlKey, candidate);
    _api.baseUrl = candidate;
    _online = await _api.isReachable();
    notifyListeners();
    return true;
  }

  /// Pushes the current preferences to the newsroom, best-effort.
  Future<void> syncDevice() async {
    if (!_initialised) return;
    try {
      await _api.registerDevice(DeviceProfile(
        deviceId: storage.deviceId,
        locale: _locale,
        theme: _themeMode,
        breakingAlerts: _breakingAlerts,
        dailyDigest: _dailyDigest,
      ));
    } on ApiException {
      // Preferences still work locally; the server sync is a nicety.
    }
  }

  // -- bookmarks -----------------------------------------------------------

  Future<void> _refreshBookmarks() async {
    try {
      final cached = await storage.getCache(Storage.bookmarkCacheKey);
      if (cached != null) {
        final decoded = jsonDecode(cached);
        if (decoded is List) {
          _bookmarked.addAll(decoded.map((e) => (e as num).toInt()));
        }
      }
    } on Exception {
      // ignore
    }
    if (!_initialised) {
      notifyListeners();
    }
  }

  Future<void> toggleBookmark(int storyId) async {
    if (_bookmarked.contains(storyId)) {
      await removeBookmark(storyId);
    } else {
      await addBookmark(storyId);
    }
  }

  Future<void> addBookmark(int storyId) async {
    if (_bookmarked.contains(storyId)) return;
    _bookmarked.add(storyId);
    notifyListeners();
    try {
      await _api.addBookmark(deviceId: storage.deviceId, storyId: storyId);
    } on ApiException {
      // Optimistic add stands; the next sync reconciles.
    }
    await _persistBookmarks();
  }

  Future<void> removeBookmark(int storyId) async {
    if (!_bookmarked.contains(storyId)) return;
    _bookmarked.remove(storyId);
    notifyListeners();
    try {
      await _api.removeBookmark(deviceId: storage.deviceId, storyId: storyId);
    } on ApiException {
      // ignore
    }
    await _persistBookmarks();
  }

  Future<void> _persistBookmarks() async {
    await storage.putCache(
        Storage.bookmarkCacheKey, jsonEncode(_bookmarked.toList()));
  }

  Future<void> resetIdentity() async {
    await storage.resetDeviceId();
    _bookmarked.clear();
    await _refreshBookmarks();
    notifyListeners();
    unawaited(syncDevice());
  }

  Future<void> clearCache() async {
    await storage.clearCache();
    await _refreshBookmarks();
    notifyListeners();
  }

  /// Bookmarks read from the cache at startup, so the badge is right even
  /// before the newsroom answers.
  Set<int> get bookmarkedIds => Set.unmodifiable(_bookmarked);
}

/// Where the cache directory comes from at startup, isolated so it can be
/// overridden in tests.
Future<Directory> appCacheDir() async {
  return getTemporaryDirectory();
}
