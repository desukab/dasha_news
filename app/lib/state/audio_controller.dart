import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/narration.dart';
import '../models/story.dart';
import 'app_state.dart';

/// Read-aloud playback, in a voice the reader's phone already has.
///
/// The newsroom renders an espeak edition of every story, and espeak is the
/// robot voice — the reason a reader tries Listen once and never again. So the
/// app speaks the story itself, through the text-to-speech engine installed on
/// the reader's device: a Telugu voice reads the Telugu line, an English voice
/// reads the English and Tenglish ones. The newsroom's WAVs stay as the archive
/// and the fallback, but the reader's ears get a human voice.
///
/// Playback state lives here, above any one page, so leaving the audio tab
/// does not stop the story.
class AudioController extends ChangeNotifier {
  AudioController(this._appState) : _tts = FlutterTts() {
    _tts.setStartHandler(() {
      _speaking = true;
      _loading = false;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      // The story is finished, but it is still the story the bar is about, so
      // the reader can play it again rather than hunting for it in the feed.
      _speaking = false;
      _paused = false;
      _fraction = 1.0;
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      _paused = false;
      notifyListeners();
    });
    _tts.setErrorHandler((_) => _fail());
    _tts.setProgressHandler((text, start, end, word) {
      // Android resumes a paused utterance from the last reported offset, so
      // the offset has to stay live even while paused.
      _fraction = text.isNotEmpty ? (start / text.length).clamp(0.0, 1.0) : 0.0;
      notifyListeners();
    });
    // Unawaited on purpose: the voices arrive a moment after the app starts,
    // and the listeners rebuild the Listen buttons when they do.
    _loadVoices();
  }

  final AppState _appState;
  final FlutterTts _tts;

  final Set<String> _voices = {};
  bool _voicesLoaded = false;

  Story? _story;
  Narration? _narration;
  bool _speaking = false;
  bool _paused = false;
  bool _loading = false;
  double _fraction = 0.0;
  String? _error;

  Story? get nowPlaying => _story;

  bool get isPlaying => _speaking && !_paused;

  bool get isLoading => _loading;

  String? get error => _error;

  /// Elapsed playing time. The engine reports progress as an offset into the
  /// text rather than a clock, so the position is the same fraction of an
  /// honest length estimate: it moves when the voice moves and lands on the
  /// end when the story finishes.
  Duration get position =>
      Duration(milliseconds: (_fraction * _lengthMs).round());

  /// How long the story takes to read aloud, estimated from its length. The
  /// engine cannot report this, and a bar that fills is worth more than one
  /// that does not.
  Duration get duration => Duration(milliseconds: _lengthMs);

  int get _lengthMs => (_words / _wordsPerSecond * 1000)
      .round()
      .clamp(0, _maxLengthMs);

  int get _words => (_narration?.text ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;

  // Telugu is spoken more slowly per word than English, so this is the Telugu
  // rate and merely conservative for the other two registers.
  static const double _wordsPerSecond = 140 / 60;

  // Android caps a single utterance, and a short-news story is far inside it.
  static const int _maxLengthMs = 60 * 1000;

  /// Whether this story can be read aloud to this reader right now.
  ///
  /// A story is only offered for listening when the reader's phone has a voice
  /// for it: a missing voice is hidden, not replaced with noise in a language
  /// the reader did not choose.
  bool canSpeak(Story story) =>
      narrationFor(story, locale: _appState.locale, voices: _voices) != null;

  /// Starts a story. Asking for the same story again resumes it.
  Future<void> play(Story story) async {
    if (_story?.id == story.id) {
      await resume();
      return;
    }
    _story = story;
    _error = null;
    notifyListeners();

    await _loadVoices();
    final narration =
        narrationFor(story, locale: _appState.locale, voices: _voices);
    if (narration == null) {
      // The reader gets the sentence in their own language, not the engine's
      // reason for silence.
      _error = _appState.strings.audioUnavailable;
      notifyListeners();
      return;
    }
    _narration = narration;
    _fraction = 0.0;
    await _speak();
  }

  Future<void> resume() async {
    if (_story == null || _narration == null) return;
    if (!_paused) {
      // A story that finished rather than pausing starts over when the reader
      // asks for it again, which is what they asked for.
      if (!_speaking) await _speak();
      return;
    }
    _paused = false;
    notifyListeners();
    try {
      // Android keeps the offset the utterance stopped at and continues from
      // there when the same text is spoken again, so the whole line is sent
      // back rather than a truncated remainder.
      await _tts.speak(_narration!.text);
    } on Object catch (_) {
      _fail();
    }
  }

  Future<void> pause() async {
    if (!_speaking) return;
    _paused = true;
    notifyListeners();
    try {
      await _tts.pause();
    } on Object catch (_) {
      _paused = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object catch (_) {
      // The reader asked for silence; a channel that is already gone has
      // given them it.
    }
    _reset();
  }

  /// Swallows transport errors for callers that only want a best-effort stop.
  Future<void> stopQuietly() async {
    try {
      await stop();
    } on Exception {
      // ignore
    }
  }

  @override
  void dispose() {
    // Best effort: the controller is going away with the app, and a channel
    // that is already gone — no engine on a headless host — must not turn
    // disposal into an unhandled error.
    _tts.stop().then((_) {}, onError: (_, __) {});
    super.dispose();
  }

  Future<void> _speak() async {
    final narration = _narration;
    if (narration == null) return;
    _loading = true;
    notifyListeners();
    try {
      await _tts.setLanguage(ttsLanguageTags[narration.voice] ?? narration.voice);
      await _tts.speak(narration.text);
    } on Object catch (_) {
      _fail();
      return;
    }
    _loading = false;
    notifyListeners();
  }

  void _reset() {
    _story = null;
    _narration = null;
    _speaking = false;
    _paused = false;
    _loading = false;
    _fraction = 0.0;
    _error = null;
    notifyListeners();
  }

  void _fail() {
    _speaking = false;
    _paused = false;
    _loading = false;
    // The reader gets the sentence in their own language, not the engine's: a
    // TTS error names engines and voice ids that mean nothing on a phone, and
    // every other failure in the app is reported the same way.
    _error = _appState.strings.audioFailed;
    notifyListeners();
  }

  /// Asks the device which of the paper's languages it can speak.
  Future<void> _loadVoices() async {
    if (_voicesLoaded) return;
    _voicesLoaded = true;
    for (final entry in ttsLanguageTags.entries) {
      if (await _voiceInstalled(entry.value)) {
        _voices.add(entry.key);
      }
    }
    notifyListeners();
  }

  Future<bool> _voiceInstalled(String tag) async {
    try {
      if (await _tts.isLanguageAvailable(tag) != true) return false;
    } on Object catch (_) {
      // No engine answered — a headless test host has none — so the language
      // is not speakable here and Listen is hidden rather than degrading.
      return false;
    }
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      // A language the engine lists but has no voice for is not usable:
      // Android falls back to the default voice, which reads Telugu as noise.
      // Only a voice actually on the device is offered.
      return await _tts.isLanguageInstalled(tag) == true;
    } on Object catch (_) {
      // The engine could not enumerate its voices. That is a reason to be
      // permissive, not silent: it declared the language available.
      return true;
    }
  }
}
