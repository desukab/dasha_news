import '../models/story.dart';
import 'format.dart';

/// What the reader's phone reads aloud, and in which of its voices.
class Narration {
  const Narration(this.text, this.voice);

  final String text;

  /// The base language the engine is asked for: `te` or `en`.
  final String voice;
}

/// The voice that reads a register the reader chose.
///
/// Tenglish is Telugu in the Roman alphabet: a Telugu voice cannot read it and
/// an English voice is the closer fit, so it is spoken as English.
String voiceForLanguage(String language) => language == 'ten' ? 'en' : language;

/// The languages the reader's phone is asked about, in the form the engine
/// wants — a language tag with a country suffix.
const Map<String, String> ttsLanguageTags = {'te': 'te-IN', 'en': 'en-US'};

/// What the engine reads for a story, or null when it cannot read the story at
/// all.
///
/// [voices] is the set of languages the reader's phone has a voice for, so a
/// null result is the signal to hide Listen rather than degrade to noise in a
/// language the reader did not choose.
Narration? narrationFor(
  Story story, {
  required String locale,
  required Set<String> voices,
}) {
  final asked = voiceForLanguage(locale);
  // The reader's own register is tried first and the other voice only when the
  // story has no column that voice can read — a story read in the wrong
  // register beats no story at all, the same trade the headline makes.
  for (final voice in [asked, asked == 'te' ? 'en' : 'te']) {
    if (!voices.contains(voice)) continue;
    final text = speakableColumn(story, voice);
    if (text != null) return Narration(text, voice);
  }
  return null;
}

/// The column of a story a voice can actually read, or null if it has none.
///
/// A column name is not a guarantee of its contents: stories filed before the
/// newsroom's script gate landed carry English wire copy in the Telugu column,
/// and a Telugu voice reading English is noise. So a column is only read when
/// its script agrees with the voice.
String? speakableColumn(Story story, String voice) {
  final teluguVoice = voice == 'te';
  final columns = teluguVoice
      ? [story.bodyTe, story.leadTe, story.headlineTe]
      : [story.bodyEn, story.bodyTen, story.headlineEn, story.headlineTen];
  for (final column in columns) {
    if (column == null) continue;
    final text = column.trim();
    if (text.isEmpty) continue;
    final scriptAgrees =
        teluguVoice ? hasTeluguScript(text) : !hasTeluguScript(text);
    if (scriptAgrees) return text;
  }
  return null;
}
