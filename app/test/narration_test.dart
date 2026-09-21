import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/narration.dart';
import 'package:dasha_news/models/story.dart';

/// Read-aloud is the one feature the headless test host cannot exercise
/// directly — there is no text-to-speech engine on it — so the decision the
/// phone has to make is pinned here instead: which story it may read, and in
/// which voice. The rule is the spec's: a story is read in a voice that can
/// pronounce it, and Listen is hidden when no such voice exists rather than
/// degrading to noise.
void main() {
  test('a Telugu story is read in the Telugu voice', () {
    final story = _story(bodyTe: 'హైదరాబాద్‌లో వరద శిబిరాలను సందర్శించారు');
    final narration = narrationFor(story,
        locale: 'te', voices: const {'te', 'en'});
    expect(narration, isNotNull);
    expect(narration!.voice, 'te');
    expect(narration.text, 'హైదరాబాద్‌లో వరద శిబిరాలను సందర్శించారు');
  });

  test('Tenglish is read by the English voice, which can pronounce it', () {
    // Tenglish is Telugu in the Roman alphabet: a Telugu voice cannot read it.
    final story = _story(bodyTen: 'Hyderabad lo KCR prakatana chesharu');
    final narration = narrationFor(story,
        locale: 'ten', voices: const {'te', 'en'});
    expect(narration, isNotNull);
    expect(narration!.voice, 'en');
    expect(narration.text, 'Hyderabad lo KCR prakatana chesharu');
  });

  test('a Telugu voice is not given English wire copy to read', () {
    // Stories filed before the script gate landed carry English in the Telugu
    // column. A Telugu voice reading it is noise, so the column is refused.
    final story = _story(bodyTe: 'Ministers review the flood relief camps');
    expect(
      speakableColumn(story, 'te'),
      isNull,
      reason: 'English in the Telugu column is not Telugu copy',
    );
  });

  test('an English voice is not given Telugu script to read', () {
    final story = _story(bodyEn: 'హైదరాబాద్‌లో వరద శిబిరాలు');
    expect(
      speakableColumn(story, 'en'),
      isNull,
      reason: 'Telugu script in the English column cannot be read aloud',
    );
  });

  test('an empty column is not read as silence', () {
    expect(speakableColumn(_story(bodyTe: '   '), 'te'), isNull);
    expect(speakableColumn(_story(), 'en'), isNull);
  });

  test('a story the reader asked for is not read in the wrong register', () {
    // A reader on Telugu gets the Telugu line even though the story also has
    // English copy: the reader's register wins, the other voice is a
    // fallback rather than a preference.
    final story = _story(
      bodyTe: 'హైదరాబాద్‌లో వరద శిబిరాలను సందర్శించారు',
      bodyEn: 'Flood camps reviewed in Hyderabad',
    );
    final narration = narrationFor(story,
        locale: 'te', voices: const {'te', 'en'});
    expect(narration!.voice, 'te');
  });

  test('a story with no column for the asked voice falls back to the other',
      () {
    // ...and a story the reader's voice cannot read at all is still read,
    // in the other voice, rather than not being read.
    final story = _story(bodyEn: 'Flood camps reviewed in Hyderabad');
    final narration = narrationFor(story,
        locale: 'te', voices: const {'te', 'en'});
    expect(narration, isNotNull);
    expect(narration!.voice, 'en');
  });

  test('Listen is hidden when the phone has no voice for the story', () {
    // The whole point: no Telugu voice and no English copy means the story is
    // not offered for listening, instead of being read in a voice that cannot
    // pronounce it.
    final teluguOnly = _story(bodyTe: 'హైదరాబాద్‌లో వరద శిబిరాలు');
    expect(
      narrationFor(teluguOnly, locale: 'te', voices: const {'en'}),
      isNull,
    );
  });

  test('Listen is hidden when the phone has no voice at all', () {
    final story = _story(bodyTe: 'హైదరాబాద్‌లో వరద శిబిరాలు');
    expect(narrationFor(story, locale: 'te', voices: const {}), isNull);
  });

  test('a story with no copy in any language is not read', () {
    expect(
      narrationFor(_story(), locale: 'te', voices: const {'te', 'en'}),
      isNull,
    );
  });

  test('a voiceless phone with a Tenglish reader is hidden, not English-read',
      () {
    // Tenglish maps to the English voice, so a phone with neither voice
    // cannot offer the story in either register.
    final story = _story(bodyTen: 'Hyderabad lo KCR prakatana chesharu');
    expect(narrationFor(story, locale: 'ten', voices: const {'te'}), isNull);
  });

  test('the lead stands in for a story with no body', () {
    final story = _story(leadTe: 'హైదరాబాద్‌లో వరద శిబిరాలను సందర్శించారు');
    final narration = narrationFor(story,
        locale: 'te', voices: const {'te'});
    expect(narration!.text, 'హైదరాబాద్‌లో వరద శిబిరాలను సందర్శించారు');
  });

  test('the headline stands in for a story with no body and no lead', () {
    final story = _story(headlineTe: 'వరద శిబిరాల్లో సందర్శన');
    final narration = narrationFor(story,
        locale: 'te', voices: const {'te'});
    expect(narration!.text, 'వరద శిబిరాల్లో సందర్శన');
  });
}

Story _story({
  String? headlineTe,
  String? headlineTen,
  String? headlineEn,
  String? leadTe,
  String? bodyTe,
  String? bodyTen,
  String? bodyEn,
}) =>
    Story(
      id: 1,
      clusterId: 'cluster-1',
      slug: 'flood-camps',
      section: 'telangana',
      status: 'published',
      importance: 0.8,
      isBreaking: false,
      isDeveloping: false,
      headlineTe: headlineTe,
      headlineTen: headlineTen,
      headlineEn: headlineEn,
      leadTe: leadTe,
      bodyTe: bodyTe,
      bodyTen: bodyTen,
      bodyEn: bodyEn,
    );
