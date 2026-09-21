import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/api_client.dart';

/// The client is the app's only seam against the newsroom, so its error
/// mapping is what decides whether a reader sees "offline" or "something went
/// wrong". These tests pin that mapping to the contract the UI relies on.
void main() {
  ApiClient client(http.Client mock) =>
      ApiClient(baseUrl: 'http://newsroom.test', client: mock);

  /// Telugu must survive the wire: the default Response encoder is latin1.
  http.Response ok([Object? body]) => http.Response.bytes(
        utf8.encode(jsonEncode(body ?? <String, dynamic>{})),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  test('the feed is decoded into a page of stories', () async {
    final api = client(MockClient((request) async {
      expect(request.url.path, '/v1/feed');
      expect(request.url.queryParameters['language'], 'te');
      expect(request.url.queryParameters['page'], '1');
      return ok({
        'items': [_feedStory],
        'total': 1,
        'page': 1,
        'page_size': 20,
        'has_more': false,
      });
    }));

    final page = await api.feed(language: 'te');
    expect(page.items.single.headline('te'), 'తల్లి వార్త');
    expect(page.hasMore, isFalse);
    api.close();
  });

  test('a relative media URL is left alone; the caller resolves it', () async {
    final api = client(MockClient((request) async => ok(_feedStory)));

    final story = await api.story(1);
    expect(story.imageUrl, '/media/posters/1.jpg');
    expect(story.audioUrl, '/media/audio/1.mp3');
    api.close();
  });

  test('a socket failure becomes an offline error, not a crash', () async {
    final api = client(MockClient((_) async => throw const SocketException('')));

    await expectLater(api.feed(language: 'te'), throwsA(isA<ApiException>()));
    try {
      await api.feed(language: 'te');
      fail('expected an ApiException');
    } on ApiException catch (exc) {
      expect(exc.isOffline, isTrue);
      expect(exc.isClientError, isFalse);
    }
    api.close();
  });

  test('a timeout is reported as offline, because cached content still helps',
      () async {
    final api = client(MockClient((_) async => throw TimeoutException('')));

    try {
      await api.feed(language: 'te');
      fail('expected an ApiException');
    } on ApiException catch (exc) {
      expect(exc.isOffline, isTrue);
    }
    api.close();
  });

  test('a 4xx is a client error and reaches the reader as one', () async {
    final api = client(MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'bad request'}), 400)));

    try {
      await api.feed(language: 'te');
      fail('expected an ApiException');
    } on ApiException catch (exc) {
      expect(exc.statusCode, 400);
      expect(exc.message, 'bad request');
      expect(exc.isClientError, isTrue);
      expect(exc.isOffline, isFalse);
    }
    api.close();
  });

  test('an empty 200 body is a valid response, not a malformed one', () async {
    final api = client(MockClient((_) async => http.Response('', 200)));

    expect((await api.feed(language: 'te')).items, isEmpty);
    api.close();
  });

  test('a non-JSON body is rejected rather than silently swallowed', () async {
    final api = client(MockClient((_) async => http.Response('<html/>', 200)));

    try {
      await api.feed(language: 'te');
      fail('expected an ApiException');
    } on ApiException catch (exc) {
      expect(exc.message, contains('malformed'));
    }
    api.close();
  });

  test('a bookmark round trip echoes the server state', () async {
    final api = client(MockClient((request) async {
      expect(request.url.path, '/v1/bookmarks/7');
      expect(request.method, 'POST');
      return ok({'bookmarked': true});
    }));
    expect(await api.addBookmark(deviceId: 'dev', storyId: 7), isTrue);
    api.close();
  });

  test('a tip is accepted only when the newsroom returns an id', () async {
    final api = client(MockClient((_) async => ok({'id': 42})));
    expect(await api.submitTip(deviceId: 'dev', body: 'అప్రమత్తం'), 42);
    api.close();

    final rejected = client(MockClient((_) async => ok({'ok': true})));
    try {
      await rejected.submitTip(deviceId: 'dev', body: 'x');
      fail('expected an ApiException');
    } on ApiException catch (exc) {
      expect(exc.statusCode, 0);
    }
    rejected.close();
  });

  test('health is unreachable only when nothing answered', () async {
    final up = client(MockClient((_) async => ok({'status': 'ok'})));
    expect(await up.isReachable(), isTrue);
    up.close();

    final refused = client(MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'no'}), 503)));
    expect(await refused.isReachable(), isFalse);
    refused.close();
  });

  test('a story carries no desk-only field even when the wire copy does',
      () async {
    final api = client(MockClient((_) async => ok(_feedStory)));
    final story = await api.story(1);
    // The reader API does not send evidence or source counts, but a phone in
    // the field can be talking to a server one release behind, and the model
    // has nowhere to put them: the fields are gone from the object, so an
    // unknown key is dropped rather than carried into the UI.
    expect(story.headline('te'), 'తల్లి వార్త');
    expect(story.headline('en'), 'Mother story');
    expect(story.body('te'), 'వాక్యం ఇక్కడ ఉంది.');
    expect(story.mandal, 'Hayatnagar');
    api.close();
  });
}

const Map<String, dynamic> _feedStory = {
  'id': 1,
  'cluster_id': 'c1',
  'slug': 'talli-vartha',
  'section': 'telangana',
  'status': 'published',
  'importance': 0.8,
  // The reader API does not send these. They are here because a phone can be
  // talking to a server one release behind, and the model must drop them
  // rather than render them.
  'evidence_score': 0.9,
  'num_sources': 3,
  'is_breaking': false,
  'is_developing': false,
  'headline_te': 'తల్లి వార్త',
  'headline_en': 'Mother story',
  'body_te': 'వాక్యం ఇక్కడ ఉంది.',
  'published_at': '2026-06-01T10:00:00Z',
  'image_url': '/media/posters/1.jpg',
  'audio_url': '/media/audio/1.mp3',
  'mandal': 'Hayatnagar',
  'district': 'Hyderabad',
  'state': 'Telangana',
};
