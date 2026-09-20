/// Tests for the editor app's only seam against the newsroom.
///
/// These assert what actually crosses the wire -- the path, the method, the
/// signed token header, the body -- because the client is the place where a
/// missing `/editor` prefix or a dropped `evidence_level` would silently turn
/// into a 404 or a fact recorded at the wrong certainty. The responses are
/// hand-rolled rather than recorded, so a shape change in the newsroom has to
/// be reflected here deliberately.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/core/config.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// A transport that records the last request and answers it from a callback.
///
/// `MockClient` from `package:http/testing.dart` would suffice for the happy
/// path, but these tests also need to inspect the request the client built,
/// which means keeping a handle to it.
class RecordingTransport extends http.BaseClient {
  RecordingTransport(this._respond);

  final Future<http.StreamedResponse> Function(http.Request request) _respond;

  http.Request? last;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw ArgumentError('the test transport expects a body-carrying Request');
    }
    last = request;
    calls += 1;
    return _respond(request);
  }

  @override
  void close() {}

  Map<String, dynamic> get lastBody {
    final raw = last!.body;
    if (raw.isEmpty) return const {};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Uri get lastUri => last!.url;
  String get lastMethod => last!.method;
}

/// The client under test, paired with the transport that watched its traffic.
class Wire {
  Wire(this.client, this.transport);

  final EditorApiClient client;
  final RecordingTransport transport;
}

http.StreamedResponse _jsonResponse(Object? body, {int status = 200}) {
  final payload = body is String ? body : jsonEncode(body);
  final bytes = utf8.encode(payload);
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([bytes]),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

Wire _wire(
  Future<http.StreamedResponse> Function(http.Request) respond, {
  String base = 'http://test.local',
  String? token,
}) {
  final transport = RecordingTransport(respond);
  return Wire(
    EditorApiClient.withTransport(
      transport,
      baseUrlReader: () => base,
      token: token,
    ),
    transport,
  );
}

const _storyJson = {
  'id': 42,
  'cluster_id': 'c-1',
  'slug': 'hyderabad-rains',
  'section': 'general',
  'status': 'draft',
  'origin': 'automated',
  'editor_locked': false,
  'needs_review': true,
  'num_sources': 3,
  'importance': 0.8,
  'evidence_score': 0.66,
  'corrections_count': 0,
  'version': 1,
};

const _submissionJson = {
  'id': 1,
  'headline': 'హైదరాబాద్‌లో పాఠశాల బట్టలు',
  'body': 'నేను మా పాఠశాలలో చూశాను, బట్టలు తడిగా ఉన్నాయి.',
  'category': 'education',
  'location_text': 'హైదరాబాద్',
  'contact': 'శేఖర్ రెడ్డి',
  'media_path': null,
  'status': 'new',
  'triage_note': null,
  'story_id': null,
  'created_at': '2026-09-20T08:30:00+00:00',
};

void main() {
  // --------------------------------------------------------------------------
  // The wire: paths, methods, the signed header
  // --------------------------------------------------------------------------

  test('login posts the credentials to the session endpoint and keeps the token',
      () async {
    final wire = _wire((req) async => _jsonResponse({'token': 'signed-token'}));
    final token = await wire.client.login(
        email: 'desk@example.news', password: 'hunter2-password');

    expect(token, 'signed-token');
    expect(wire.client.token, 'signed-token');
    expect(wire.transport.lastMethod, 'POST');
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/session');
    expect(wire.transport.lastBody, {
      'email': 'desk@example.news',
      'password': 'hunter2-password',
    });
  });

  test('a missing token in the response is a failure, not an empty session',
      () async {
    final wire = _wire((req) async => _jsonResponse({}));
    await expectLater(
      wire.client.login(email: 'a@b.c', password: 'long-enough-password'),
      throwsA(isA<EditorApiException>()),
    );
  });

  test('every request carries the signed token once issued', () async {
    final wire = _wire(
      (req) async {
        expect(req.headers['X-Dasha-Token'], 'signed-token');
        return _jsonResponse({'user': {'id': 1, 'email': 'desk@example.news'}});
      },
      token: 'signed-token',
    );
    await wire.client.whoami();
    expect(wire.transport.calls, 1);
  });

  test('a user map with no id is an unattached session, not a type cast',
      () async {
    final wire = _wire((req) async => _jsonResponse({'user': {}}));
    try {
      await wire.client.whoami();
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.message, 'The session is not attached to an account');
    }
  });

  test('no token means no auth header rather than a blank one', () async {
    late String? sent;
    final wire = _wire((req) async {
      sent = req.headers['X-Dasha-Token'];
      return _jsonResponse({'user': {'id': 1, 'email': 'd@example.news'}});
    });
    await wire.client.whoami();
    expect(sent, isNull);
  });

  test('the /editor prefix is added exactly once, however it is configured',
      () async {
    final withSlash =
        _wire((req) async => _jsonResponse({'user': {'id': 1, 'email': 'a@b.c'}}),
        base: 'http://test.local/');
    await withSlash.client.whoami();
    expect(withSlash.transport.lastUri.toString(), 'http://test.local/editor/session');

    final alreadyPrefixed =
        _wire((req) async => _jsonResponse({'user': {'id': 1, 'email': 'a@b.c'}}),
        base: 'http://test.local/editor/');
    await alreadyPrefixed.client.whoami();
    expect(alreadyPrefixed.transport.lastUri.toString(),
        'http://test.local/editor/session');
  });

  // --------------------------------------------------------------------------
  // The queue
  // --------------------------------------------------------------------------

  test('the story list filters become query parameters', () async {
    final wire = _wire((req) async => _jsonResponse({
          'items': [_storyJson],
          'total': 1,
          'has_more': false,
        }));
    final page = await wire.client.stories(
      status: 'draft',
      origin: 'manual',
      needsAttention: true,
      page: 2,
    );

    expect(wire.transport.lastUri.queryParameters, {
      'status': 'draft',
      'origin': 'manual',
      'needs_attention': 'true',
      'page': '2',
    });
    expect(page.total, 1);
    expect(page.hasMore, isFalse);
    expect(page.items.single.id, 42);
    expect(page.items.single.needsReview, isTrue);
  });

  test('a story is fetched by id rather than searched for in the queue',
      () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    final story = await wire.client.story(42);
    expect(story.id, 42);
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/stories/42');
    expect(wire.transport.lastMethod, 'GET');
  });

  test('creating and editing a story use the collection and the item path',
      () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    await wire.client.createStory({'headline_te': 'తల్లి', 'section': 'general'});
    expect(wire.transport.lastMethod, 'POST');
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/stories');
    expect(wire.transport.lastBody['headline_te'], 'తల్లి');

    await wire.client.updateStory(42, {'status': 'published'});
    expect(wire.transport.lastMethod, 'PATCH');
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/stories/42');
    expect(wire.transport.lastBody, {'status': 'published'});
  });

  test('lifecycle actions post to the story action path with an empty body',
      () async {
    final wire = _wire((req) async => _jsonResponse({'status': 'published'}));
    final result = await wire.client.storyAction(42, 'publish');
    expect(result['status'], 'published');
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/stories/42/publish');
    expect(wire.transport.lastBody, isEmpty);
  });

  test('regenerate and unlock are the two sides of the precedence rule',
      () async {
    final wire = _wire((req) async => _jsonResponse({'ok': true}));
    await wire.client.regenerate(42);
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/stories/42/regenerate');
    await wire.client.unlock(42);
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/stories/42/unlock');
  });

  // --------------------------------------------------------------------------
  // Facts
  // --------------------------------------------------------------------------

  test('a fact carries its evidence level separately from the prose', () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    await wire.client.addFact(42,
        textTe: 'అధికారిక ప్రకటన',
        textEn: 'official statement',
        evidenceLevel: 'official');
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/stories/42/facts');
    expect(wire.transport.lastBody, {
      'text_te': 'అధికారిక ప్రకటన',
      'text_en': 'official statement',
      'evidence_level': 'official',
    });
  });

  test('an absent English rendering is omitted rather than sent empty', () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    await wire.client.addFact(42, textTe: 'వాదన');
    expect(wire.transport.lastBody, {
      'text_te': 'వాదన',
      'evidence_level': 'claim',
    });
    expect(wire.transport.lastBody.containsKey('text_en'), isFalse);
  });

  test('withdrawing a fact deletes it so the audit trail keeps the assertion',
      () async {
    final wire = _wire((req) async => _jsonResponse('', status: 204));
    await wire.client.withdrawFact(7);
    expect(wire.transport.lastMethod, 'DELETE');
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/facts/7');
  });

  // --------------------------------------------------------------------------
  // Reader submissions: the tip queue the desk triages by hand
  // --------------------------------------------------------------------------

  test('the tip queue is newest first and carries the unread count', () async {
    final wire = _wire((req) async => _jsonResponse({
          'items': [_submissionJson],
          'total': 1,
          'has_more': false,
          'new_count': 2,
        }));
    final page = await wire.client.submissions(status: 'new');

    expect(wire.transport.lastMethod, 'GET');
    expect(wire.transport.lastUri.path, '/editor/submissions');
    expect(wire.transport.lastUri.queryParameters, {'status': 'new', 'page': '1'});
    expect(page.newCount, 2);
    expect(page.items.single.id, 1);
    expect(page.items.single.headline, 'హైదరాబాద్‌లో పాఠశాల బట్టలు');
    expect(page.items.single.body, contains('మా పాఠశాలలో'));
  });

  test('the tip queue is asked for every status when no filter is set',
      () async {
    final wire = _wire((req) async => _jsonResponse({
          'items': [],
          'total': 0,
          'has_more': false,
          'new_count': 0,
        }));
    await wire.client.submissions();
    expect(wire.transport.lastUri.queryParameters, {'page': '1'});
    expect(wire.transport.lastUri.queryParameters.containsKey('status'), isFalse);
  });

  test('one tip is fetched by id for the detail view', () async {
    final wire = _wire((req) async => _jsonResponse(_submissionJson));
    final tip = await wire.client.submission(1);
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/submissions/1');
    expect(tip.contact, 'శేఖర్ రెడ్డి');
    expect(tip.locationText, 'హైదరాబాద్');
  });

  test('triage posts the label and the desk note, and nothing else', () async {
    final wire = _wire((req) async => _jsonResponse({
          ..._submissionJson,
          'status': 'verified',
          'triage_note': 'confirmed by phone',
        }));
    final updated = await wire.client.triageSubmission(1,
        status: 'verified', note: 'confirmed by phone');

    expect(wire.transport.lastMethod, 'POST');
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/submissions/1/triage');
    expect(wire.transport.lastBody, {
      'status': 'verified',
      'note': 'confirmed by phone',
    });
    expect(updated.status, 'verified');
    expect(updated.triageNote, 'confirmed by phone');
  });

  test('a triage without a note omits the key rather than sending it blank',
      () async {
    final wire = _wire((req) async => _jsonResponse(_submissionJson));
    await wire.client.triageSubmission(1, status: 'triaged');
    expect(wire.transport.lastBody, {'status': 'triaged'});
    expect(wire.transport.lastBody.containsKey('note'), isFalse);
  });

  test('turning a tip into a story posts only the fields the desk filled in',
      () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    await wire.client.submissionToStory(1,
        headlineTe: 'హైదరాబాద్ బట్టలు',
        section: 'education',
        district: 'హైదరాబాద్');

    expect(wire.transport.lastMethod, 'POST');
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/submissions/1/story');
    expect(wire.transport.lastBody, {
      'headline_te': 'హైదరాబాద్ బట్టలు',
      'section': 'education',
      'district': 'హైదరాబాద్',
    });
  });

  test('a tip with no desk overrides sends an empty body', () async {
    final wire = _wire((req) async => _jsonResponse(_storyJson));
    await wire.client.submissionToStory(1);
    expect(wire.transport.lastBody, isEmpty);
  });

  // --------------------------------------------------------------------------
  // The automated newsroom
  // --------------------------------------------------------------------------

  test('pipeline health is the counts the desk triages on', () async {
    final wire = _wire((req) async => _jsonResponse({
          'articles_failed': 2,
          'jobs_stuck': 1,
          'stories_needing_review': 5,
          'stories_editor_locked': 3,
          'needs_attention': true,
        }));
    final health = await wire.client.pipelineHealth();
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/pipeline');
    expect(health.articlesFailed, 2);
    expect(health.jobsStuck, 1);
    expect(health.storiesNeedingReview, 5);
    expect(health.storiesEditorLocked, 3);
    expect(health.needsAttention, isTrue);
  });

  test('failures split into articles and jobs, both retryable', () async {
    final wire = _wire((req) async => _jsonResponse({
          'articles': [
            {'id': 9, 'url': 'https://example.news/a', 'reason': '403 blocked'}
          ],
          'jobs': [
            {'id': 3, 'kind': 'summarize', 'status': 'failed', 'attempts': 4}
          ],
          'total': 2,
          'has_more': true,
        }));
    final failures = await wire.client.pipelineFailures();
    expect(failures.articles.single.url, 'https://example.news/a');
    expect(failures.jobs.single.attempts, 4);
    expect(failures.hasMore, isTrue);
  });

  test('retrying an article posts to the pipeline retry path', () async {
    final wire = _wire((req) async => _jsonResponse({'ok': true}));
    await wire.client.retryArticle(9);
    expect(wire.transport.lastMethod, 'POST');
    expect(wire.transport.lastUri.toString(),
        'http://test.local/editor/pipeline/retry/9');
  });

  // --------------------------------------------------------------------------
  // Accounts
  // --------------------------------------------------------------------------

  test('users are listed and invited over their own paths', () async {
    final wire = _wire((req) async {
      if (req.method == 'POST') {
        return _jsonResponse({
          'user': {'id': 3, 'email': 'new@example.news', 'role': 'editor'},
        });
      }
      return _jsonResponse({
        'users': [
          {'id': 1, 'email': 'owner@example.news', 'role': 'admin'},
          {'id': 2, 'email': 'desk@example.news', 'role': 'editor'},
        ],
      });
    });
    final users = await wire.client.users();
    expect(users.map((u) => u.role), ['admin', 'editor']);

    await wire.client.createUser(
      email: 'new@example.news',
      password: 'a-very-long-password',
      role: 'editor',
      displayName: 'New Desk',
    );
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/users');
    expect(wire.transport.lastBody['email'], 'new@example.news');
    expect(wire.transport.lastBody['display_name'], 'New Desk');
  });

  test('a user can be demoted without losing the page', () async {
    final wire = _wire((req) async => _jsonResponse({
          'user': {'id': 2, 'email': 'desk@example.news', 'role': 'user'},
        }));
    final user = await wire.client.updateUser(2, role: 'user');
    expect(wire.transport.lastMethod, 'PATCH');
    expect(wire.transport.lastUri.toString(), 'http://test.local/editor/users/2');
    expect(user.role, 'user');
    expect(wire.transport.lastBody, {'role': 'user'});
  });

  // --------------------------------------------------------------------------
  // Refusals and broken transports
  // --------------------------------------------------------------------------

  test('a 403 surfaces the newsroom\'s reason verbatim', () async {
    final wire = _wire((req) async => _jsonResponse(
          {'detail': 'This action needs editor privileges.'},
          status: 403,
        ));
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.status, 403);
      expect(exc.message, 'This action needs editor privileges.');
      expect(exc.isSessionDead, isFalse);
    }
  });

  test('a 401 is a dead session so the caller can drop the token', () async {
    final wire = _wire((req) async => _jsonResponse(
          {'detail': 'Session expired'},
          status: 401,
        ));
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.status, 401);
      expect(exc.isSessionDead, isTrue);
    }
  });

  test('a body the newsroom could not form is still a refusal with a status',
      () async {
    final wire =
        _wire((req) async => _jsonResponse('not json at all', status: 500));
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.status, 500);
      expect(exc.message, contains('500'));
    }
  });

  test('a refusal with no detail falls back to the status code', () async {
    final wire = _wire((req) async => _jsonResponse({}, status: 422));
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.status, 422);
    }
  });

  test('an unreachable newsroom is reported as offline, not as a crash',
      () async {
    final wire = _wire((req) async {
      throw SocketException('Failed host lookup: \'test.local\'');
    });
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.status, 0);
      expect(exc.isOffline, isTrue);
      expect(exc.message, contains('Cannot reach the newsroom'));
    }
  });

  test('a refused handshake is distinguished from a missing host', () async {
    // HandshakeException implements SocketException, so a catch in the wrong
    // order silently re-labels a refused TLS negotiation as an unreachable
    // host -- which sends the desk looking for a network problem it does not
    // have.
    final wire = _wire((req) async {
      throw HandshakeException('Connection terminated during handshake');
    });
    try {
      await wire.client.story(42);
      fail('the client should have raised');
    } on EditorApiException catch (exc) {
      expect(exc.isOffline, isFalse);
      expect(exc.message, contains('refused the connection'));
    }
  });

  test('a 204 is a success with an empty body', () async {
    final wire = _wire((req) async => _jsonResponse('', status: 204));
    expect(await wire.client.storyAction(42, 'hold'), isEmpty);
  });

  // --------------------------------------------------------------------------
  // The shapes the desk renders
  // --------------------------------------------------------------------------

  test('the three publication languages are configured in desk order', () {
    expect(supportedLocales, ['te', 'ten', 'en']);
    expect(evidenceLevels.first, 'fact');
    expect(evidenceLevels.last, 'unverified');
    expect(editorialStatuses, containsAll(['draft', 'published', 'killed']));
  });

  test('a user is an editor if the newsroom said so, and not otherwise', () {
    for (final role in const ['admin', 'editor', 'user']) {
      final user = NewsroomUser(id: 1, email: 'a@b.c', role: role);
      expect(user.isAdmin, role == 'admin');
      expect(user.isEditor, role != 'user');
    }
  });

  test('a withdrawn fact is still a parsed fact, just not a live one', () {
    final fact = FactView.fromJson({
      'id': 1,
      'text_te': 'వాదన',
      'evidence_level': 'allegation',
      'status': 'withdrawn',
      'rank': 2,
    });
    expect(fact.isActive, isFalse);
    expect(fact.evidenceLevel, 'allegation');
  });
}
