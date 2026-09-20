/// The editor app's only seam against the newsroom.
///
/// Every request carries the signed session token the newsroom issued, in the
/// header a mobile webview can set. The client knows nothing about roles:
/// whether an account may do something is decided server-side on every
/// request, and this client reports the refusal it gets back rather than
/// pre-judging the outcome.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:dasha_editor/core/config.dart';
import 'package:dasha_editor/models/story.dart';

/// A refusal from the newsroom, or a transport failure.
///
/// The desk needs to see *why*: "403 — this action needs editor privileges"
/// is actionable, "something went wrong" is not. 401 is treated as a dead
/// session and the caller clears the token instead of looping on it.
class EditorApiException implements Exception {
  const EditorApiException(this.status, this.message, {this.isSessionDead = false});

  factory EditorApiException.fromStatus(int status, String message) {
    return EditorApiException(status, message, isSessionDead: status == 401);
  }

  final int status;
  final String message;
  final bool isSessionDead;

  bool get isOffline =>
      status == 0 && (message.contains('Socket') || message.contains('Failed host'));

  @override
  String toString() => message;
}

class EditorApiClient {
  EditorApiClient({String Function()? baseUrlReader, this.token})
      : _readBaseUrl = baseUrlReader ?? (() => defaultBaseUrl),
        _transport = null;

  /// Test seam: inject a transport instead of the network.
  @visibleForTesting
  EditorApiClient.withTransport(
    http.Client transport, {
    required String Function() baseUrlReader,
    this.token,
  })  : _transport = transport,
        _readBaseUrl = baseUrlReader;

  final String Function() _readBaseUrl;
  final http.Client? _transport;
  String? token;

  String get _baseUrl => _readBaseUrl().replaceAll(RegExp(r'/+$'), '');
  bool get hasToken => token != null && token!.isNotEmpty;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _baseUrl.endsWith('/editor') ? _baseUrl : '$_baseUrl/editor';
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> get _authHeaders {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (hasToken) {
      headers['X-Dasha-Token'] = token!;
    }
    return headers;
  }

  Future<Map<String, dynamic>> _json(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final client = _transport ?? http.Client();
    http.Response response;
    try {
      response = await client.send(http.Request(method, uri)..headers.addAll(_authHeaders)
            ..body = body == null ? '' : jsonEncode(body)).then(http.Response.fromStream);
    } on HandshakeException catch (exc) {
      // HandshakeException implements SocketException, so this must be caught
      // first: a refused TLS negotiation is a live host that did not like us,
      // not an unreachable one.
      throw EditorApiException(0, 'The newsroom refused the connection: ${exc.message}');
    } on SocketException catch (exc) {
      throw EditorApiException(0, 'Cannot reach the newsroom: ${exc.message}');
    } on http.ClientException catch (exc) {
      throw EditorApiException(0, 'The request failed: ${exc.message}');
    } finally {
      if (_transport == null) {
        client.close();
      }
    }

    if (response.statusCode == 204) {
      return <String, dynamic>{};
    }

    Map<String, dynamic> decoded = const {};
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is Map<String, dynamic>) {
        decoded = parsed;
      } else if (parsed is List) {
        decoded = <String, dynamic>{'items': parsed};
      }
    } on FormatException {
      decoded = const {};
    }

    if (response.statusCode >= 400) {
      final detail = decoded['detail'] as String? ??
          decoded['message'] as String? ??
          'The newsroom responded ${response.statusCode}';
      throw EditorApiException.fromStatus(response.statusCode, detail);
    }
    return decoded;
  }

  // --------------------------------------------------------------------------
  // Session
  // --------------------------------------------------------------------------

  /// Log in. Returns the token the newsroom issued; nothing else is kept.
  ///
  /// A bad password and an unknown email return the same message from the
  /// server, so this surface cannot be used to enumerate accounts.
  Future<String> login({required String email, required String password}) async {
    final json = await _json('POST', _uri('/session'), body: {
      'email': email.trim(),
      'password': password,
    });
    final token = json['token'] as String?;
    if (token == null || token.isEmpty) {
      throw const EditorApiException(0, 'The newsroom did not issue a session');
    }
    this.token = token;
    return token;
  }

  Future<NewsroomUser> whoami() async {
    final json = await _json('GET', _uri('/session'));
    final user = json['user'] as Map<String, dynamic>?;
    // A user map without an id is a session the newsroom did not really
    // attach; reporting it as such beats surfacing a type cast to the desk.
    if (user == null || user['id'] == null) {
      throw const EditorApiException(0, 'The session is not attached to an account');
    }
    return NewsroomUser.fromJson(user);
  }

  Future<void> logout() async {
    try {
      await _json('DELETE', _uri('/session'));
    } finally {
      token = null;
    }
  }

  // --------------------------------------------------------------------------
  // The desk's queue
  // --------------------------------------------------------------------------

  Future<Page<StoryDetail>> stories({
    String? status,
    String? origin,
    bool needsAttention = false,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (status != null) query['status'] = status;
    if (origin != null) query['origin'] = origin;
    if (needsAttention) query['needs_attention'] = 'true';
    final json = await _json('GET', _uri('/stories', query));
    return Page.fromJson(json, StoryDetail.fromJson);
  }

  Future<StoryDetail> story(int id) async {
    final json = await _json('GET', _uri('/stories/$id'));
    return StoryDetail.fromJson(json);
  }

  Future<StoryDetail> createStory(Map<String, Object?> fields) async {
    final json = await _json('POST', _uri('/stories'), body: fields);
    return StoryDetail.fromJson(json);
  }

  Future<StoryDetail> updateStory(int id, Map<String, Object?> fields) async {
    final json = await _json('PATCH', _uri('/stories/$id'), body: fields);
    return StoryDetail.fromJson(json);
  }

  /// Any of the transitions the newsroom exposes under /{action}: publish,
  /// unpublish, approve, archive, feature, breaking, hold, correct, note.
  Future<Map<String, dynamic>> storyAction(
    int id,
    String action, {
    Map<String, Object?>? body,
  }) async {
    return _json('POST', _uri('/stories/$id/$action'), body: body ?? const {});
  }

  Future<Map<String, dynamic>> regenerate(int id) async {
    return _json('POST', _uri('/stories/$id/regenerate'));
  }

  Future<Map<String, dynamic>> unlock(int id) async {
    return _json('POST', _uri('/stories/$id/unlock'));
  }

  Future<void> addFact(int storyId,
      {required String textTe, String? textEn, String evidenceLevel = 'claim'}) async {
    await _json('POST', _uri('/stories/$storyId/facts'), body: {
      'text_te': textTe,
      'text_en': ?textEn,
      'evidence_level': evidenceLevel,
    });
  }

  Future<void> withdrawFact(int factId) async {
    await _json('DELETE', _uri('/facts/$factId'));
  }

  // --------------------------------------------------------------------------
  // Reader submissions: tips the desk triages by hand
  // --------------------------------------------------------------------------

  /// The reader-tip queue, newest first.
  ///
  /// Contact details travel with a tip, so the newsroom gates this on the
  /// editor session rather than a key compiled into the app.
  Future<SubmissionPage> submissions({String? status, int page = 1}) async {
    final query = <String, String>{'page': '$page'};
    if (status != null) query['status'] = status;
    final json = await _json('GET', _uri('/submissions', query));
    return SubmissionPage.fromJson(json);
  }

  Future<SubmissionView> submission(int id) async {
    final json = await _json('GET', _uri('/submissions/$id'));
    return SubmissionView.fromJson(json);
  }

  /// Move a tip along the review queue. A triage label, not a publish.
  Future<SubmissionView> triageSubmission(
    int id, {
    required String status,
    String? note,
  }) async {
    final json = await _json('POST', _uri('/submissions/$id/triage'), body: {
      'status': status,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return SubmissionView.fromJson(json);
  }

  /// Turn a verified tip into a draft story.
  ///
  /// The newsroom keeps the tip's evidence level honest -- it lands as an
  /// unverified claim attributed to the submitter -- and this returns the
  /// draft the desk then writes and publishes.
  Future<StoryDetail> submissionToStory(
    int id, {
    String? headlineTe,
    String? section,
    String? district,
  }) async {
    final json = await _json('POST', _uri('/submissions/$id/story'), body: {
      if (headlineTe != null && headlineTe.isNotEmpty) 'headline_te': headlineTe,
      if (section != null && section.isNotEmpty) 'section': section,
      if (district != null && district.isNotEmpty) 'district': district,
    });
    return StoryDetail.fromJson(json);
  }

  // --------------------------------------------------------------------------
  // The automated newsroom
  // --------------------------------------------------------------------------

  Future<PipelineHealth> pipelineHealth() async {
    final json = await _json('GET', _uri('/pipeline'));
    return PipelineHealth.fromJson(json);
  }

  Future<PipelineFailures> pipelineFailures({int page = 1}) async {
    final json = await _json('GET', _uri('/pipeline/failures', {'page': '$page'}));
    return PipelineFailures.fromJson(json);
  }

  Future<Map<String, dynamic>> retryArticle(int articleId) async {
    return _json('POST', _uri('/pipeline/retry/$articleId'));
  }

  // --------------------------------------------------------------------------
  // Accounts, admin-only. The server re-checks the role every time.
  // --------------------------------------------------------------------------

  Future<List<NewsroomUser>> users() async {
    final json = await _json('GET', _uri('/users'));
    final rows = json['users'] as List? ?? const [];
    return rows
        .map((e) => NewsroomUser.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<NewsroomUser> createUser({
    required String email,
    required String password,
    required String role,
    String? displayName,
  }) async {
    final json = await _json('POST', _uri('/users'), body: {
      'email': email.trim(),
      'password': password,
      'role': role,
      'display_name': ?displayName,
    });
    return NewsroomUser.fromJson(json['user'] as Map<String, dynamic>? ?? const {});
  }

  Future<NewsroomUser> updateUser(int id, {String? role, bool? isActive}) async {
    final json = await _json('PATCH', _uri('/users/$id'), body: {
      'role': ?role,
      'is_active': ?isActive,
    });
    return NewsroomUser.fromJson(json['user'] as Map<String, dynamic>? ?? const {});
  }
}
