/// The newsroom session: one token, one account, held in plain view.
///
/// Nothing about the newsroom is compiled into the app. The token is a
/// credential the server issued after a login; it is cached so a reopened
/// app does not force a re-login, and discarded the moment the server
/// refuses it -- a 401 means the session is dead, not that retrying will
/// help.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/core/config.dart';
import 'package:dasha_editor/models/story.dart';

class SessionState extends ChangeNotifier {
  SessionState() : _client = EditorApiClient(baseUrlReader: _fallbackBaseUrl);

  final EditorApiClient _client;

  NewsroomUser? _user;
  bool _loading = true;
  String? _error;
  String? _baseUrl;

  NewsroomUser? get user => _user;
  bool get loading => _loading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isEditor => _user?.isEditor ?? false;
  String? get error => _error;
  EditorApiClient get client => _client;
  String get baseUrl => _baseUrl ?? defaultBaseUrl;

  static String _fallbackBaseUrl() {
    // Resolved lazily through the instance once _baseUrl is known; used only
    // before restore() has populated it.
    return defaultBaseUrl;
  }

  /// Load the held token and confirm it still authorises.
  Future<void> restore() async {
    _loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _baseUrl = prefs.getString(baseUrlKey) ?? defaultBaseUrl;
      final token = prefs.getString(tokenKey);
      if (token == null || token.isEmpty) {
        _user = null;
        _loading = false;
        notifyListeners();
        return;
      }
      _client.token = token;
      _user = await _client.whoami();
      _error = null;
    } on EditorApiException catch (exc) {
      // A token the server no longer honours is not a session: drop it and
      // show the login screen rather than looping on a dead credential.
      if (exc.isSessionDead) {
        await _clearToken();
        _user = null;
      } else {
        _error = exc.message;
        _user = null;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(baseUrlKey, trimmed);
    notifyListeners();
  }

  Future<void> login({required String email, required String password}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final token = await _client.login(email: email, password: password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, token);
      _user = await _client.whoami();
    } on EditorApiException catch (exc) {
      _error = exc.message;
      _user = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _client.logout();
    } on EditorApiException {
      // The server may already consider this session dead; either way the
      // local copy has to go.
    }
    await _clearToken();
    _user = null;
    _error = null;
    notifyListeners();
  }

  Future<void> _clearToken() async {
    _client.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
  }
}
