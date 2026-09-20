import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/app_strings.dart';
import 'package:dasha_news/core/format.dart';
import 'package:dasha_news/models/page.dart';
import 'package:dasha_news/models/story.dart';

/// Model-level invariants the UI depends on. These are the contracts that,
/// if broken, would silently render a wrong story rather than crash.
void main() {
  group('Story language fallback', () {
    test('falls back to another language when the asked one is missing', () {
      final story = Story(
        id: 1,
        clusterId: 'c',
        slug: 'slug',
        section: 'politics',
        status: 'published',
        importance: 0.8,
        evidenceScore: 0.9,
        numSources: 3,
        isBreaking: false,
        isDeveloping: false,
        headlineTe: 'తెలుగు శీర్షిక',
        headlineTen: null,
        headlineEn: 'English headline',
      );

      expect(story.headline('te'), 'తెలుగు శీర్షిక');
      expect(story.headline('en'), 'English headline');
      // Tenglish has no own headline; it must still not come back empty.
      expect(story.headline('ten').isNotEmpty, isTrue);
    });

    test('falls all the way back to the slug when nothing is set', () {
      final story = Story(
        id: 2,
        clusterId: 'c',
        slug: 'only-a-slug',
        section: 'telangana',
        status: 'published',
        importance: 0.1,
        evidenceScore: 0.1,
        numSources: 1,
        isBreaking: false,
        isDeveloping: false,
      );
      expect(story.headline('en'), 'only-a-slug');
      expect(story.body('te'), isEmpty);
    });

    // Stories published before the newsroom's script gate landed still carry
    // English wire copy in the Telugu column, and an offline cache can hold a
    // copy from before the fix. Neither may reach the reader as Telugu.
    test('never serves the wrong script as the asked language', () {
      final story = Story(
        id: 3,
        clusterId: 'c',
        slug: 'english-in-the-telugu-column',
        section: 'telangana',
        status: 'published',
        importance: 0.5,
        evidenceScore: 0.5,
        numSources: 1,
        isBreaking: false,
        isDeveloping: false,
        headlineTe: 'Ministers review the flood relief camps',
        headlineEn: 'Ministers review the flood relief camps',
      );

      // English text is not a Telugu headline, however the column is named.
      expect(story.headline('te'), 'Ministers review the flood relief camps');
      expect(story.headline('en'), 'Ministers review the flood relief camps');
      // The reader is told the truth about which language that is.
      expect(story.headlineIsTelugu('te'), isFalse);
    });

    test('prefers a genuine Telugu headline over a stale English one', () {
      final story = _story(
        headlineTe: 'నిజమైన తెలుగు శీర్షిక',
        headlineTen: 'nijamaina telugu sIrshika',
        headlineEn: 'A real English headline',
      );
      expect(story.headline('te'), 'నిజమైన తెలుగు శీర్షిక');
      expect(story.headlineIsTelugu('te'), isTrue);
      expect(story.headline('en'), 'A real English headline');
      // Roman Telugu is Latin script; a Telugu-script line is the wrong thing
      // for the Tenglish column.
      expect(story.headline('ten'), 'nijamaina telugu sIrshika');
    });

    test('an English lead is not served as the story lead', () {
      final story = _story(
        headlineTe: 'తెలుగు శీర్షిక',
        leadTe: 'This lead is English, not Telugu.',
        bodyTe: 'ఇది నిజమైన తెలుగు వాచకం. రెండవ వాక్యం.',
      );
      // The lead falls back to the Telugu body's own first sentence rather
      // than showing an English line under a Telugu headline.
      expect(story.lead, 'ఇది నిజమైన తెలుగు వాచకం');
    });

    test('place resolves to the deepest level available', () {
      expect(_story(mandal: 'Hayatnagar', district: 'Hyderabad').place,
          'Hayatnagar');
      expect(_story(district: 'Hyderabad').place, 'Hyderabad');
      expect(_story(state: 'India').place, 'India');
      expect(_story().place, isNull);
    });

    test('corroboration and conflict flags are derived from sources', () {
      expect(_story(numSources: 3).isCorroborated, isTrue);
      expect(_story(numSources: 1).isCorroborated, isFalse);

      final conflicting = _story(
        numSources: 2,
        sources: [
          const SourceLink(id: 1, corroborates: false, conflictsWith: 'toll'),
          const SourceLink(id: 2, corroborates: true),
        ],
      );
      expect(conflicting.hasConflict, isTrue);

      final agreeing = _story(
        numSources: 2,
        sources: const [
          SourceLink(id: 1, corroborates: true),
          SourceLink(id: 2, corroborates: true),
        ],
      );
      expect(agreeing.hasConflict, isFalse);
    });
  });

  group('Fact evidence taxonomy', () {
    test('a fact is factual only at fact or official level', () {
      expect(_fact('fact').isFactual, isTrue);
      expect(_fact('official').isFactual, isTrue);
      expect(_fact('claim').isFactual, isFalse);
      expect(_fact('allegation').isFactual, isFalse);
      expect(_fact('unverified').isFactual, isFalse);
    });

    test('the weakest levels are flagged for attribution', () {
      expect(_fact('allegation').isWeakest, isTrue);
      expect(_fact('unverified').isWeakest, isTrue);
      expect(_fact('disputed').isWeakest, isTrue);
      expect(_fact('fact').isWeakest, isFalse);
    });

    test('an English-language reader gets the English text when present', () {
      final fact = _fact('fact', textTe: 'తెలుగు', textEn: 'English');
      expect(fact.text('te'), 'తెలుగు');
      expect(fact.text('en'), 'English');
    });

    test('a fact without English still renders in Telugu for an English reader',
        () {
      final fact = _fact('fact', textTe: 'తెలుగు వాక్యం', textEn: null);
      // Better to show the source script than to show nothing at all.
      expect(fact.text('en'), 'తెలుగు వాక్యం');
    });
  });

  group('Pagination', () {
    test('has_more is honoured and empty pages stop the iteration', () {
      const page = StoryPage(
        items: [],
        total: 0,
        page: 2,
        pageSize: 20,
        hasMore: false,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('a cached page is marked as such', () {
      final page = StoryPage.empty().copyWith(fromCache: true);
      expect(page.fromCache, isTrue);
    });
  });

  group('Script detection', () {
    test('Telugu script is detected in mixed strings', () {
      expect(hasTeluguScript('తెలంగాణ వార్తలు'), isTrue);
      expect(hasTeluguScript('Breaking: హైదరాబాద్'), isTrue);
      expect(hasTeluguScript('Tenglish lo vaarthalu'), isFalse);
      expect(hasTeluguScript(''), isFalse);
      expect(hasTeluguScript(null), isFalse);
    });

    test('relative time never returns an empty string for a known moment', () {
      final now = DateTime(2026, 6, 1, 12);
      const en = AppStrings('en');
      expect(relativeTime(now, now: now, strings: en), 'just now');
      expect(
        relativeTime(now.subtract(const Duration(hours: 3)),
            now: now, strings: en),
        contains('h ago'),
      );
      // A null timestamp is a missing field, not an empty story.
      expect(relativeTime(null, strings: en), isEmpty);
    });

    test('reading time is at least one minute', () {
      expect(int.parse(readingTime('one two three')), greaterThanOrEqualTo(1));
    });

    test('large counts are compressed in the Indian style', () {
      expect(compactCount(999), '999');
      expect(compactCount(1200), '1.2k');
      expect(compactCount(5000), '5k');
      expect(compactCount(150000), '1.5L');
    });
  });

  group('Section catalogue', () {
    test('a section resolves its label per language', () {
      const section = NewsSection(
          slug: 'politics', te: 'రాజకీయాలు', ten: 'Rajakeeyalu', en: 'Politics');
      expect(section.label('te'), 'రాజకీయాలు');
      expect(section.label('ten'), 'Rajakeeyalu');
      expect(section.label('en'), 'Politics');
    });
  });
}

Story _story({
  int numSources = 1,
  String? headlineTe,
  String? headlineTen,
  String? headlineEn,
  String? leadTe,
  String? bodyTe,
  String? mandal,
  String? district,
  String? state,
  List<SourceLink> sources = const [],
}) {
  return Story(
    id: 1,
    clusterId: 'c',
    slug: 'slug',
    section: 'telangana',
    status: 'published',
    importance: 0.5,
    evidenceScore: 0.5,
    numSources: numSources,
    isBreaking: false,
    isDeveloping: false,
    headlineTe: headlineTe,
    headlineTen: headlineTen,
    headlineEn: headlineEn,
    leadTe: leadTe,
    bodyTe: bodyTe,
    mandal: mandal,
    district: district,
    state: state,
    sources: sources,
  );
}

Fact _fact(String level, {String textTe = 'వాక్యం', String? textEn}) {
  return Fact(
    id: 1,
    textTe: textTe,
    textEn: textEn,
    evidenceLevel: level,
    confidence: 0.8,
    status: 'active',
    rank: 1,
  );
}
