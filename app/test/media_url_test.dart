import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/media_url.dart';
import 'package:dasha_news/models/story.dart';

/// The audio edition is served by the newsroom, and the newsroom names its own
/// machine when it builds the URL. This is the test that says which URLs reach
/// a phone and which do not.
void main() {
  const base = 'https://news.dasha.example';

  group('a loopback origin is the newsroom naming its own machine', () {
    test('localhost is rewritten to the newsroom the app talks to', () {
      expect(
        resolveMediaUrl('http://localhost:8000/media/audio/te/story-9.wav', base),
        'https://news.dasha.example/media/audio/te/story-9.wav',
      );
    });

    test('127.0.0.1 is rewritten too', () {
      expect(
        resolveMediaUrl('http://127.0.0.1:8000/media/audio/te/story-9.wav', base),
        'https://news.dasha.example/media/audio/te/story-9.wav',
      );
    });

    test('the emulator host alias is rewritten', () {
      expect(
        resolveMediaUrl('http://10.0.2.2:8000/media/x.wav', base),
        'https://news.dasha.example/media/x.wav',
      );
    });

    test('the path and query survive the rewrite', () {
      expect(
        resolveMediaUrl('http://localhost:8000/media/a%20b.wav?t=1', base),
        'https://news.dasha.example/media/a%20b.wav?t=1',
      );
    });
  });

  group('a public origin is honoured', () {
    test('a source site hosting its own photograph is untouched', () {
      const url = 'https://cm.telangana.gov.in/wp-content/uploads/2026/09/p.jpg';
      expect(resolveMediaUrl(url, base), url);
    });

    test('a CDN is untouched', () {
      const url = 'https://cdn.dasha.example/media/audio/te/story-9.wav';
      expect(resolveMediaUrl(url, base), url);
    });
  });

  group('a relative URL is a path on the newsroom', () {
    test('a leading slash joins without doubling', () {
      expect(resolveMediaUrl('/media/audio/te/story-9.wav', base),
          'https://news.dasha.example/media/audio/te/story-9.wav');
    });

    test('a base that already ends in a slash does not gain two', () {
      expect(resolveMediaUrl('/media/x.wav', '$base/'),
          'https://news.dasha.example/media/x.wav');
    });
  });

  group('absence', () {
    test('null stays null', () => expect(resolveMediaUrl(null, base), isNull));
    test('empty stays null', () => expect(resolveMediaUrl('', base), isNull));
  });

  group('a story carries its own resolved photograph', () {
    Story storyWith(String? imageUrl) => Story(
          id: 1,
          clusterId: '1',
          slug: 'story-1',
          section: 'state',
          status: 'published',
          importance: 1.0,
          evidenceScore: 0,
          numSources: 1,
          isBreaking: false,
          isDeveloping: false,
          imageUrl: imageUrl,
        );

    test('a bare path from the newsroom becomes absolute', () {
      expect(storyWith('/wp-content/uploads/2026/02/p.jpg').imageFor(base),
          'https://news.dasha.example/wp-content/uploads/2026/02/p.jpg');
    });

    test('a loopback image origin is rewritten like the audio one is', () {
      expect(storyWith('http://localhost:8000/media/i/912.jpg').imageFor(base),
          'https://news.dasha.example/media/i/912.jpg');
    });

    test('a source site hosting its own photograph is untouched', () {
      const url = 'https://cm.telangana.gov.in/wp-content/uploads/p.jpg';
      expect(storyWith(url).imageFor(base), url);
    });

    test('a story with no photograph has none to resolve', () {
      expect(storyWith(null).imageFor(base), isNull);
    });
  });
}
