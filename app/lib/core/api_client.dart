import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/page.dart';
import '../models/story.dart';
import 'config.dart';

/// Every call the app makes to the newsroom, in one place.
///
/// The client is deliberately dumb: it maps JSON to models and raises
/// [ApiException] on anything unexpected. Retries, caching and offline
/// fallback live in the services layer, so that a policy change never touches
/// the transport.
class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  String baseUrl;
  final http.Client _client;

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'X-Client': 'dasha-news/flutter',
  };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) {
        params[key] = value.toString();
      }
    });
    return Uri.parse('$base$path').replace(queryParameters: params);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final response = await _client
          .get(_uri(path, query), headers: _headers)
          .timeout(Duration(seconds: readTimeout.inSeconds + 20));
      return _decode(response);
    } on SocketException catch (exc) {
      throw ApiException.offline(exc.message);
    } on http.ClientException catch (exc) {
      throw ApiException.network(exc.message);
    } on TimeoutException {
      throw ApiException.timeout();
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    try {
      final response = await _client
          .post(_uri(path, query),
              headers: {
                ..._headers,
                if (body != null) 'Content-Type': 'application/json',
              },
              body: body == null ? null : jsonEncode(body))
          .timeout(Duration(seconds: readTimeout.inSeconds + 20));
      return _decode(response);
    } on SocketException catch (exc) {
      throw ApiException.offline(exc.message);
    } on http.ClientException catch (exc) {
      throw ApiException.network(exc.message);
    } on TimeoutException {
      throw ApiException.timeout();
    }
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path, [
    Map<String, dynamic>? query,
  ]) async {
    try {
      final response = await _client
          .delete(_uri(path, query), headers: _headers)
          .timeout(const Duration(seconds: 20));
      return _decode(response);
    } on SocketException catch (exc) {
      throw ApiException.offline(exc.message);
    } on http.ClientException catch (exc) {
      throw ApiException.network(exc.message);
    } on TimeoutException {
      throw ApiException.timeout();
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.trim();
    if (body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return <String, dynamic>{};
      }
      throw ApiException(response.statusCode, 'empty response');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(response.statusCode, 'unexpected response shape');
      }
      if (response.statusCode >= 400) {
        final detail = decoded['detail'];
        throw ApiException(
            response.statusCode, detail is String ? detail : 'request failed');
      }
      return decoded;
    } on FormatException {
      throw ApiException(response.statusCode, 'malformed response');
    }
  }

  // -- public endpoints -----------------------------------------------------

  Future<StoryPage> feed({
    required String language,
    String? section,
    String? district,
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json = await _getJson('/v1/feed', {
      'language': language,
      if (section != null && section.isNotEmpty) 'section': section,
      if (district != null && district.isNotEmpty) 'district': district,
      'page': page,
      'page_size': pageSize,
    });
    return StoryPage.fromJson(json);
  }

  Future<StoryPage> breaking({
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json =
        await _getJson('/v1/breaking', {'page': page, 'page_size': pageSize});
    return StoryPage.fromJson(json);
  }

  Future<StoryPage> developing({
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json =
        await _getJson('/v1/developing', {'page': page, 'page_size': pageSize});
    return StoryPage.fromJson(json);
  }

  Future<SectionCatalogue> sections() async {
    final json = await _getJson('/v1/sections');
    return SectionCatalogue.fromJson(json);
  }

  Future<List<String>> districts() async {
    final json = await _getJson('/v1/districts');
    final list = json['districts'];
    if (list is! List) return const [];
    return list.map((e) => e.toString()).toList(growable: false);
  }

  Future<Story> story(int id) async {
    final json = await _getJson('/v1/story/$id');
    return Story.fromJson(json);
  }

  Future<Story> storyBySlug(String slug) async {
    final json = await _getJson('/v1/story/by-slug/${Uri.encodeComponent(slug)}');
    return Story.fromJson(json);
  }

  Future<StoryPage> search({
    required String query,
    required String language,
    int limit = 20,
  }) async {
    final json = await _getJson('/v1/search', {
      'q': query,
      'language': language,
      'limit': limit,
    });
    return StoryPage.fromJson(json);
  }

  Future<List<Story>> bookmarks({
    required String deviceId,
    int page = 1,
    int pageSize = defaultPageSize,
  }) async {
    final json = await _getJson('/v1/bookmarks', {
      'device_id': deviceId,
      'page': page,
      'page_size': pageSize,
    });
    return StoryPage.fromJson(json).items;
  }

  Future<bool> addBookmark({required String deviceId, required int storyId}) async {
    final json = await _postJson('/v1/bookmarks/$storyId', query: {
      'device_id': deviceId,
    });
    return json['bookmarked'] == true;
  }

  Future<bool> removeBookmark(
      {required String deviceId, required int storyId}) async {
    final json = await _deleteJson('/v1/bookmarks/$storyId', {
      'device_id': deviceId,
    });
    return json['bookmarked'] != true;
  }

  Future<void> recordHistory({
    required String deviceId,
    required int storyId,
    int readSeconds = 0,
    bool completed = false,
  }) async {
    await _postJson('/v1/history/$storyId', query: {
      'device_id': deviceId,
      'read_seconds': readSeconds,
      'completed': completed,
    });
  }

  Future<DeviceProfile> registerDevice(DeviceProfile profile) async {
    final json = await _postJson('/v1/device', body: {
      'device_id': profile.deviceId,
      'locale': profile.locale,
      'theme': profile.theme,
      'breaking_alerts': profile.breakingAlerts,
      'daily_digest': profile.dailyDigest,
    });
    return DeviceProfile.fromJson(json);
  }

  Future<int> submitTip({
    required String deviceId,
    required String body,
    String? category,
    String? locationText,
    String? contact,
  }) async {
    final json = await _postJson('/v1/submissions', body: {
      'device_id': deviceId,
      'body': body,
      if (category != null) 'category': category,
      if (locationText != null) 'location_text': locationText,
      if (contact != null) 'contact': contact,
    });
    final id = json['id'];
    if (id is num) return id.toInt();
    throw const ApiException(0, 'submission was not accepted');
  }

  Future<bool> isReachable() async {
    try {
      await _getJson('/v1/health');
      return true;
    } on ApiException {
      // A 4xx/5xx still proves the newsroom answered.
      return false;
    }
  }

  void close() => _client.close();
}

/// A transport failure the UI can present sensibly.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message, {this.kind = ApiFailure.other});

  ApiException.offline([String? message])
      : statusCode = 0,
        message = message ?? 'no network connection',
        kind = ApiFailure.offline;

  ApiException.network([String? message])
      : statusCode = 0,
        message = message ?? 'the request could not be sent',
        kind = ApiFailure.network;

  ApiException.timeout()
      : statusCode = 0,
        message = 'the newsroom did not answer in time',
        kind = ApiFailure.timeout;

  final int statusCode;
  final String message;
  final ApiFailure kind;

  /// The newsroom is unreachable; cached content is worth showing.
  bool get isOffline =>
      kind == ApiFailure.offline || kind == ApiFailure.timeout;

  /// The request reached the newsroom but was refused (bad input, rate limit).
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

enum ApiFailure { offline, network, timeout, other }
