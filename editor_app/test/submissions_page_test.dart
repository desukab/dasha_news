/// The reader-tip queue, as the desk sees it.
///
/// What these tests pin down is the contract between the tip and the story:
/// the queue shows what the submitter sent and where they say they are, the
/// detail view shows the whole text exactly as received, triage moves a label
/// in place, and the only way a tip becomes a story is the desk's explicit
/// "create a draft". Nothing here publishes.
library;

import 'dart:convert';

import 'package:dasha_editor/core/api_client.dart';
import 'package:dasha_editor/state/session_state.dart';
import 'package:dasha_editor/state/submissions_state.dart';
import 'package:dasha_editor/state/workqueue_state.dart';
import 'package:dasha_editor/ui/submissions_page.dart';
import 'package:dasha_editor/ui/story_detail_page.dart';
import 'package:dasha_editor/ui/workqueue_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tipBody =
    'నేను ఉదయం మా పాఠశాలకి వెళ్లాను. అక్కడ వర్షం కారణంగా నీరు నిలిచింది. '
    'పిల్లలు బట్టలు తడిగా ఉన్నాయి. కొన్ని తరగతులు జరగలేదు.';

Map<String, Object?> _tip({
  int id = 1,
  String status = 'new',
  int? storyId,
  String contact = 'శేఖర్ రెడ్డి',
}) =>
    {
      'id': id,
      'headline': 'పాఠశాలలో నీరు నిలిచింది',
      'body': _tipBody,
      'category': 'education',
      'location_text': 'హైదరాబాద్',
      'contact': contact,
      'media_path': null,
      'status': status,
      'triage_note': null,
      'story_id': storyId,
      'created_at': '2026-09-20T08:30:00+00:00',
    };

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

/// A transport that answers every request from a callback, so the page under
/// test can be pumped against a newsroom that says exactly what the test
/// needs it to say, and no request ever touches the network.
class _Transport extends http.BaseClient {
  _Transport(this.respond);

  final Future<Map<String, dynamic>> Function(
    String path,
    String method,
    Map<String, dynamic> body,
    Map<String, String> query,
  ) respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      throw ArgumentError('the test transport expects a body-carrying Request');
    }
    Map<String, dynamic> decoded = const {};
    if (request.body.isNotEmpty) {
      decoded = jsonDecode(request.body) as Map<String, dynamic>;
    }
    try {
      final body = await respond(
        request.url.path,
        request.method,
        decoded,
        request.url.queryParameters,
      );
      return _response(body, 200);
    } on EditorApiException catch (exc) {
      return _response({'detail': exc.message}, exc.status);
    }
  }

  @override
  void close() {}
}

http.StreamedResponse _response(Map<String, dynamic> body, int status) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([bytes]),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

EditorApiClient _client(
  Future<Map<String, dynamic>> Function(
    String path,
    String method,
    Map<String, dynamic> body,
    Map<String, String> query,
  ) respond,
) {
  return EditorApiClient.withTransport(
    _Transport(respond),
    baseUrlReader: () => 'http://test.local',
    token: 'signed-token',
  );
}

/// A session whose client is the stub, so the pages read a newsroom the test
/// controls instead of the one on the wire.
class _StubSession extends SessionState {
  _StubSession(this.stub);
  final EditorApiClient stub;

  @override
  EditorApiClient get client => stub;
}

Widget _harness(Widget child, EditorApiClient client) {
  // SessionState sits above MaterialApp, as it does in main.dart, so a pushed
  // route can still read the session: the detail page is a second route, not a
  // child of the home route. WorkQueueState lives in the home route only,
  // exactly as the app's own gate places it.
  return ChangeNotifierProvider<SessionState>(
    create: (_) => _StubSession(client),
    child: MaterialApp(
      home: ChangeNotifierProvider<WorkQueueState>(
        create: (_) => WorkQueueState(client),
        // The page lives inside a Scaffold in production (the queue's
        // TabBarView), which is also what the FilterChips need.
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'dasha_editor.token': 'signed-token',
      'dasha_editor.base_url': 'http://test.local',
    });
  });

  testWidgets('the queue shows the tips the newsroom has, newest first',
      (tester) async {
    final client = _client((path, method, body, query) async {
      return {
        'items': [_tip(), _tip(id: 2, status: 'triaged')],
        'total': 2,
        'has_more': false,
        'new_count': 2,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    expect(find.text('పాఠశాలలో నీరు నిలిచింది'), findsNWidgets(2));
    expect(find.textContaining('హైదరాబాద్'), findsNWidgets(2));
    // The contact travels with the tip so the desk can follow up; it is never
    // shown in place of the tip itself.
    expect(find.text('contact: శేఖర్ రెడ్డి'), findsNWidgets(2));
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(2));
  });

  testWidgets('an empty queue says so plainly, without an error banner',
      (tester) async {
    final client = _client((path, method, body, query) async {
      return {
        'items': const <Object?>[],
        'total': 0,
        'has_more': false,
        'new_count': 0,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    expect(find.text('No tip is waiting on the desk.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('a refused queue is reported, not swapped for an empty list',
      (tester) async {
    final client = _client((path, method, body, query) async {
      throw EditorApiException(403, 'This action needs editor privileges.');
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    expect(find.text('Could not reach the newsroom'), findsOneWidget);
    expect(find.text('This action needs editor privileges.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('opening a tip shows the whole text exactly as received',
      (tester) async {
    final client = _client((path, method, body, query) async {
      return {
        'items': [_tip()],
        'total': 1,
        'has_more': false,
        'new_count': 1,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    expect(find.text('Tip #1'), findsOneWidget);
    // The detail view carries the reader's words verbatim -- correcting the
    // spelling here would destroy the record the desk is verifying against.
    expect(find.text(_tipBody), findsOneWidget);
    expect(find.text('WHAT THE READER SENT'), findsOneWidget);
    expect(find.text('Where'), findsOneWidget);
    expect(find.text('Contact'), findsOneWidget);
  });

  testWidgets('triage moves the label without leaving the page', (tester) async {
    var status = 'new';
    final client = _client((path, method, body, query) async {
      if (path == '/editor/submissions/1/triage') {
        status = body['status'] as String;
        return _tip(status: status);
      }
      return {
        'items': [_tip(status: status)],
        'total': 1,
        'has_more': false,
        'new_count': status == 'new' ? 1 : 0,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'verified'));
    await tester.pumpAndSettle();

    // The tip stays where it was, with its new label.
    expect(state.items.single.status, 'verified');
    expect(state.newCount, 0);
    expect(find.text('Create draft story'), findsOneWidget);
  });

  testWidgets('a tip already turned into a story offers no second conversion',
      (tester) async {
    final client = _client((path, method, body, query) async {
      return {
        'items': [_tip(storyId: 90, status: 'verified')],
        'total': 1,
        'has_more': false,
        'new_count': 0,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.enabled, isFalse);
    expect(find.text('Already story #90'), findsOneWidget);
  });

  testWidgets('creating a draft lands on the story the desk has to write',
      (tester) async {
    final client = _client((path, method, body, query) async {
      if (path == '/editor/submissions/1/story') {
        return Map<String, dynamic>.from(_storyJson);
      }
      return {
        'items': [_tip(status: 'verified')],
        'total': 1,
        'has_more': false,
        'new_count': 0,
      };
    });
    final state = SubmissionsState(client);

    await tester.pumpWidget(_harness(SubmissionsPage(state: state), client));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create draft story'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create draft'));
    await tester.pumpAndSettle();

    // The tip is now a draft, and the page the desk needs open is the draft:
    // the tip queue is finished with it.
    expect(find.byType(StoryDetailPage), findsOneWidget);
  });

  testWidgets('the queue tab names the unread tips', (tester) async {
    final client = _client((path, method, body, query) async {
      if (path == '/editor/submissions') {
        return {
          'items': [_tip()],
          'total': 1,
          'has_more': false,
          'new_count': 3,
        };
      }
      if (path == '/editor/stories') {
        return {'items': const <Object?>[], 'total': 0, 'has_more': false};
      }
      if (path == '/editor/pipeline') {
        return {
          'articles_failed': 0,
          'jobs_stuck': 0,
          'stories_needing_review': 0,
          'stories_editor_locked': 0,
          'needs_attention': false,
        };
      }
      return {};
    });

    await tester.pumpWidget(_harness(const WorkQueuePage(), client));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('Reader tips'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
    // The desk's own queue is untouched by the new tab.
    expect(find.text('Needs attention'), findsOneWidget);
  });
}
