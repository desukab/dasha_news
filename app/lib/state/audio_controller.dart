import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api_client.dart';
import '../core/media_url.dart';
import '../models/story.dart';
import 'app_state.dart';

/// Read-aloud playback.
///
/// The audio edition is a genuine second format, not a gimmick: a reader
/// commuting or cooking gets the same editorial contract as a reader reading.
/// Playback state lives here, above any one page, so leaving the audio tab
/// does not stop the story.
class AudioController extends ChangeNotifier {
  AudioController(this._appState) : _player = AudioPlayer() {
    _player.playerStateStream.listen((state) {
      _playing = state.playing;
      _processing = state.processingState;
      notifyListeners();
    });
    _player.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });
    _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
      notifyListeners();
    });
  }

  final AppState _appState;
  final AudioPlayer _player;

  Story? _story;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  ProcessingState _processing = ProcessingState.idle;
  String? _error;

  Story? get nowPlaying => _story;

  bool get isPlaying => _playing;

  bool get isLoading => _processing == ProcessingState.loading;

  Duration get position => _position;

  Duration get duration => _duration;

  String? get error => _error;

  bool get canPlay => _story?.audioUrl != null || _story?.hasAudio == true;

  /// Starts a story. Asking for the same story again just resumes.
  Future<void> play(Story story) async {
    if (_story?.id == story.id) {
      await resume();
      return;
    }
    _story = story;
    _error = null;
    notifyListeners();

    final url = _resolvedUrl(story);
    if (url == null) {
      _error = _appState.strings.audioUnavailable;
      notifyListeners();
      return;
    }
    try {
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await _player.play();
    } on Exception catch (_) {
      // The reader gets the sentence in their own language, not the
      // transport's: a player exception names codecs and status codes that
      // mean nothing on a phone, and every other failure in the app is
      // reported the same way.
      _error = _appState.strings.audioFailed;
      notifyListeners();
    }
  }

  /// The newsroom returns an absolute media URL. When it names its own
  /// loopback machine — which its default `public_base_url` does — the reader's
  /// phone would try to play a file from itself, so the origin is replaced with
  /// the newsroom the app actually talks to. Relative URLs resolve the same way.
  String? _resolvedUrl(Story story) {
    return resolveMediaUrl(story.audioUrl, _appState.baseUrl);
  }

  Future<void> resume() async {
    if (_story == null) return;
    try {
      await _player.play();
    } on Exception catch (_) {
      _error = _appState.strings.audioFailed;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    _story = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _error = null;
    notifyListeners();
  }

  Future<void> seekTo(Duration position) async {
    await _player.seek(position);
  }

  Future<void> skipForward() async {
    await _player.seek(_position + const Duration(seconds: 15));
  }

  Future<void> skipBackward() async {
    await _player.seek(_position - const Duration(seconds: 15));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Swallows transport errors for callers that only want a best-effort stop.
  Future<void> stopQuietly() async {
    try {
      await stop();
    } on ApiException {
      // ignore
    }
  }
}
