/// The reader-tip queue, as one observable list.
///
/// The state is the place where two product rules live: a triaged tip stays in
/// the list instead of jumping out from under the desk, and the badge is the
/// server's count rather than a local guess. Both are asserted here so a
/// refactor that "tidies" them away is caught.
library;

import 'dart:convert';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/models/story.dart';
import 'package:dasha_editor/state/submissions_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const _storyJson = {
  'id': 90,
  'cluster_id': 'c-tip-1',
  'slug': 'tip-1',
  'section': 'general',
  'status': 'draft',
  'origin': 'manual',
  'editor_locked': true,
  'needs_review': true,
  'num_sources': 0,
  'importance': 0.5,
  'evidence_score': 0.3,
  'corrections_count': 0,
  'version': 1,
};

Map<String, Object?> _tip({
  int id = 1,
  String status = 'new',
  String headline = 'హైదరాబాద్‌లో పాఠశాల బట్టలు',
  String body = 'మా పాఠశాలలో బట్టలు తడిగా ఉన్నాయి.',
  int? storyId,
}) {
  return {
    'id': id,
    'headline': headline,
    'body': body,
    'category': null,
    'location_text': 'హైదరాబాద్',
    'contact': 'శేఖర్ రెడ్డి',
    'media_path': null,
    'status': status,
    'triage_note': null,
    'story_id': storyId,
    'created_at': '2026-09-20T08:30:00+00:00',
  };
}

http.StreamedResponse _ok(Object? body, {int status = 200}) {
  final payload = body is String ? body : jsonEncode(body);
  final bytes = utf8.encode(payload);
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([bytes]),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

/// A transport that answers from a callback, so the queue's behaviour is
/// asserted against what actually crossed the wire.
class _Transport extends http.BaseClient {
  _Transport(this.respond);

  final Future<http.StreamedResponse> Function(http.Request) respond;
  http.Request? last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw ArgumentError('the test transport expects a body-carrying Request');
    }
    last = request;
    return respond(request);
  }

  @override
  void close() {}
}

SubmissionsState _state(
    Future<http.StreamedResponse> Function(http.Request) respond,
    {Recording? recorder}) {
  final transport = _Transport((req) async {
    recorder?.last = req;
    return respond(req);
  });
  return SubmissionsState(EditorApiClient.withTransport(
    transport,
    baseUrlReader: () => 'http://test.local',
    token: 'signed-token',
  ));
}

class Recording {
  http.Request? last;
}

/// The filter load is fire-and-forget inside the state, so the test waits for
/// the list to fill rather than guessing at a delay.
Future<void> _until(Future<bool> Function() test, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    if (await test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw StateError('the condition never became true');
}

void main() {
  test('refresh fills the list, the total and the badge', () async {
    final rec = Recording();
    final state = _state((req) async => _ok({
          'items': [_tip(), _tip(id: 2, status: 'triaged')],
          'total': 2,
          'has_more': false,
          'new_count': 1,
        }), recorder: rec);
    await state.refresh();

    expect(state.loading, isFalse);
    expect(state.error, isNull);
    expect(state.items.map((t) => t.id), [1, 2]);
    expect(state.total, 2);
    expect(state.newCount, 1);
    expect(rec.last!.url.path, '/editor/submissions');
    expect(rec.last!.url.queryParameters, {'status': 'new', 'page': '1'});
  });

  test('an unreachable newsroom reports the error rather than an empty queue',
      () async {
    final state = _state((req) async => _ok(
          {'detail': 'This action needs editor privileges.'},
          status: 403,
        ));
    await state.refresh();

    expect(state.error, 'This action needs editor privileges.');
    expect(state.items, isEmpty);
  });

  test('the empty queue is a state, not an error', () async {
    final state = _state((req) async => _ok({
          'items': const <Object?>[],
          'total': 0,
          'has_more': false,
          'new_count': 0,
        }));
    await state.refresh();

    expect(state.error, isNull);
    expect(state.items, isEmpty);
    expect(state.newCount, 0);
  });

  test('switching filter clears the list and asks for the new status', () async {
    final rec = Recording();
    final state = _state((req) async => _ok({
          'items': [_tip()],
          'total': 1,
          'has_more': false,
          'new_count': 1,
        }), recorder: rec);
    await state.refresh();

    var clearedTo = -1;
    state.addListener(() {
      if (clearedTo < 0) clearedTo = state.items.length;
    });
    state.selectFilter(SubmissionFilter.verified);
    await _until(() async => state.items.isNotEmpty);

    expect(state.filter, SubmissionFilter.verified);
    // The old tips are gone while the new page loads, so the desk never reads
    // a verified list under a "new" label.
    expect(clearedTo, 0);
    expect(rec.last!.url.queryParameters['status'], 'verified');
  });

  test('the default filter is the one the desk is behind on', () {
    expect(
        _state((req) async => _ok({
              'items': const <Object?>[],
              'total': 0,
              'has_more': false,
              'new_count': 0,
            })).filter,
        SubmissionFilter.newTips);
  });

  test('triage moves the label in place, without reordering the queue',
      () async {
    final state = _state((req) async {
      if (req.url.path.endsWith('/triage')) {
        return _ok(_tip(status: 'verified'));
      }
      return _ok({
        'items': [_tip(), _tip(id: 2)],
        'total': 2,
        'has_more': false,
        'new_count': 2,
      });
    });
    await state.refresh();
    expect(state.newCount, 2);

    await state.triage(1, status: 'verified');

    expect(state.items.first.id, 1);
    expect(state.items.first.status, 'verified');
    expect(state.items[1].status, 'new');
    // A tip that was new and no longer is takes the badge down by one.
    expect(state.newCount, 1);
  });

  test('triaging a tip that was already read leaves the badge alone', () async {
    final state = _state((req) async {
      if (req.url.path.endsWith('/triage')) {
        return _ok(_tip(status: 'rejected'));
      }
      return _ok({
        'items': [_tip(status: 'triaged')],
        'total': 1,
        'has_more': false,
        'new_count': 0,
      });
    });
    await state.refresh();

    await state.triage(1, status: 'rejected');

    expect(state.newCount, 0);
  });

  test('a refused triage surfaces the reason and keeps the tip unchanged',
      () async {
    final state = _state((req) async {
      if (req.url.path.endsWith('/triage')) {
        return _ok({'detail': 'Status "published" is not a triage state.'},
            status: 400);
      }
      return _ok({
        'items': [_tip()],
        'total': 1,
        'has_more': false,
        'new_count': 1,
      });
    });
    await state.refresh();

    await expectLater(
      state.triage(1, status: 'published'),
      throwsA(isA<EditorApiException>()),
    );
    expect(state.error, 'Status "published" is not a triage state.');
    expect(state.items.single.status, 'new');
  });

  test('converting a tip returns the draft and relinks the row', () async {
    final state = _state((req) async {
      if (req.url.path.endsWith('/story')) {
        return _ok(_storyJson, status: 201);
      }
      return _ok({
        'items': [_tip(storyId: 90, status: 'verified')],
        'total': 1,
        'has_more': false,
        'new_count': 0,
      });
    });
    await state.refresh();

    final story = await state.convert(1,
        headlineTe: 'హైదరాబాద్ బట్టలు', section: 'education');

    expect(story.status, 'draft');
    expect(story.isManual, isTrue);
    // The row is refreshed so it no longer offers a convert the newsroom
    // would refuse with a 409.
    expect(state.items.single.isConverted, isTrue);
    expect(state.items.single.storyId, 90);
  });

  test('a second convert is the server\'s refusal, not a local guess',
      () async {
    final state = _state((req) async {
      if (req.url.path.endsWith('/story')) {
        return _ok({'detail': 'This submission is already a story.'},
            status: 409);
      }
      return _ok({
        'items': [_tip(storyId: 90, status: 'verified')],
        'total': 1,
        'has_more': false,
        'new_count': 0,
      });
    });
    await state.refresh();

    await expectLater(state.convert(1), throwsA(isA<EditorApiException>()));
    expect(state.error, 'This submission is already a story.');
  });

  test('a page of tips is paged forward by the list length', () async {
    final state = _state((req) async {
      final page = int.parse(req.url.queryParameters['page']!);
      return _ok({
        'items': List.generate(25, (i) => _tip(id: page * 25 + i)),
        'total': 60,
        'has_more': page < 3,
        'new_count': 60,
      });
    });
    await state.refresh();
    expect(state.canLoadMore, isTrue);

    await state.loadMore();
    expect(state.items.length, 50);
    expect(state.canLoadMore, isTrue);
  });

  test('loadMore is a no-op while one is already in flight', () async {
    final state = _state((req) async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final page = int.parse(req.url.queryParameters['page']!);
      return _ok({
        'items': List.generate(25, (i) => _tip(id: page * 25 + i)),
        'total': 60,
        'has_more': page < 3,
        'new_count': 60,
      });
    });
    await state.refresh();

    await Future.wait([state.loadMore(), state.loadMore()]);
    // Two callers asked, but only one page was fetched for the same offset.
    expect(state.items.length, 50);
  });

  test('a tip that has become a story is not offered twice', () {
    final tip = SubmissionView.fromJson(_tip(storyId: 90, status: 'verified'));
    expect(tip.isConverted, isTrue);
    expect(tip.canConvert, isFalse);
  });


}
