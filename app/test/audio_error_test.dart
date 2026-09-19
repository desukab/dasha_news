import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dasha_news/core/api_client.dart';
import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/core/config.dart';
import 'package:dasha_news/core/storage.dart';
import 'package:dasha_news/models/story.dart';
import 'package:dasha_news/state/app_state.dart';
import 'package:dasha_news/state/audio_controller.dart';

/// The audio tab is the one place a failure used to be reported in the
/// transport's own words — "Audio could not be played: PlayerException(...)" —
/// and in English, on a Telugu-first paper. Both halves are defects: the reader
/// cannot act on a codec name, and cannot read a language they did not choose.
///
/// Only the no-edition path is asserted here: actually handing the player a URL
/// needs a platform the headless test host does not have, and the localised
/// sentence for the failure path is pinned in [strings_test].
void main() {
  testWidgets('a story with no audio edition says so in the reader\'s language',
      (tester) async {
    final app = await _appState(tester);
    final strings = AppStrings(app.locale);

    final audio = AudioController(app);
    addTearDown(audio.dispose);

    await audio.play(_story(audioUrl: null));
    await tester.pump();

    expect(audio.error, strings.audioUnavailable);
    // The English sentence the UI used to hard-code is gone.
    expect(audio.error, isNot(contains('No audio edition')));
  });
}

Story _story({required String? audioUrl}) => Story(
      id: 9,
      clusterId: 'cluster-9',
      slug: 'story-9',
      section: 'telangana',
      status: 'published',
      importance: 0.8,
      evidenceScore: 0.7,
      numSources: 2,
      isBreaking: false,
      isDeveloping: false,
      audioUrl: audioUrl,
      hasAudio: audioUrl != null,
    );

Future<AppState> _appState(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({onboardingDoneKey: true});
  final prefs = await SharedPreferences.getInstance();
  final cache = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('dasha_audio_test'),
  ))!;
  addTearDown(() => tester.runAsync(() => cache.delete(recursive: true)));
  return AppState(
    storage: _NoDiskStorage(prefs, cache),
    api: ApiClient(
      baseUrl: 'http://newsroom.test',
      client: MockClient((request) async {
        return http.Response(jsonEncode({'status': 'ok'}), 200,
            headers: const {'content-type': 'application/json'});
      }),
    ),
  );
}

class _NoDiskStorage extends Storage {
  _NoDiskStorage(super.prefs, super.cache);

  @override
  Future<void> putCache(String name, String body) async {}

  @override
  Future<String?> getCache(String name) async => null;
}
