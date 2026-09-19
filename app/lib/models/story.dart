import '../core/format.dart';
import '../core/media_url.dart';

/// The reader-facing model of a newsroom story.
///
/// This is deliberately a plain, immutable view over the JSON the newsroom
/// returns; it holds no business logic. A story card and a story detail are
/// the same object, with the heavier fields populated only on the detail page.
class Story {
  Story({
    required this.id,
    required this.clusterId,
    required this.slug,
    required this.section,
    required this.status,
    required this.importance,
    required this.evidenceScore,
    required this.numSources,
    required this.isBreaking,
    required this.isDeveloping,
    this.headlineTe,
    this.headlineTen,
    this.headlineEn,
    this.leadTe,
    this.sectionLabelTe,
    this.sectionLabelEn,
    this.statusLabelTe,
    this.district,
    this.mandal,
    this.state,
    this.imageUrl,
    this.audioUrl,
    this.hasAudio = false,
    this.publishedAt,
    this.updatedAt,
    this.bodyTe,
    this.bodyTen,
    this.bodyEn,
    this.facts = const [],
    this.sources = const [],
    this.updates = const [],
    this.correctionsCount = 0,
    this.version = 1,
    this.confidence = 0.0,
  });

  final int id;
  final String clusterId;
  final String slug;
  final String section;
  final String status;
  final double importance;
  final double evidenceScore;
  final int numSources;
  final bool isBreaking;
  final bool isDeveloping;
  final String? headlineTe;
  final String? headlineTen;
  final String? headlineEn;
  final String? leadTe;
  final String? sectionLabelTe;
  final String? sectionLabelEn;
  final String? statusLabelTe;
  final String? district;
  final String? mandal;
  final String? state;
  final String? imageUrl;
  final String? audioUrl;
  final bool hasAudio;
  final DateTime? publishedAt;
  final DateTime? updatedAt;
  final String? bodyTe;
  final String? bodyTen;
  final String? bodyEn;
  final List<Fact> facts;
  final List<SourceLink> sources;
  final List<StoryUpdate> updates;
  final int correctionsCount;
  final int version;
  final double confidence;

  /// The headline the reader asked for, falling back through the other
  /// languages rather than showing an empty string.
  String headline(String language) {
    switch (language) {
      case 'ten':
        return headlineTen?.trim().isNotEmpty == true
            ? headlineTen!.trim()
            : _fallbackHeadline;
      case 'en':
        return headlineEn?.trim().isNotEmpty == true
            ? headlineEn!.trim()
            : _fallbackHeadline;
      default:
        return headlineTe?.trim().isNotEmpty == true
            ? headlineTe!.trim()
            : _fallbackHeadline;
    }
  }

  String get _fallbackHeadline =>
      (headlineTe ?? headlineTen ?? headlineEn ?? slug).trim();

  /// Body for the chosen language, with the same fallback ordering.
  String body(String language) {
    switch (language) {
      case 'ten':
        return (bodyTen?.isNotEmpty == true ? bodyTen : _fallbackBody) ?? '';
      case 'en':
        return (bodyEn?.isNotEmpty == true ? bodyEn : _fallbackBody) ?? '';
      default:
        return (bodyTe?.isNotEmpty == true ? bodyTe : _fallbackBody) ?? '';
    }
  }

  String? get _fallbackBody => bodyTe ?? bodyTen ?? bodyEn;

  String get lead => leadTe?.isNotEmpty == true
      ? leadTe!
      : body('te').split(RegExp(r'[।.]'))[0];

  /// The photograph, on the origin the reader's phone can actually reach.
  ///
  /// The newsroom builds this URL from its own `public_base_url`, which names
  /// its own loopback machine, and sometimes hands a bare path with no origin
  /// at all. Either is unplayable on a device. Resolving at render time — not
  /// in `fromJson` — keeps the resolved origin out of the offline cache, which
  /// would otherwise go stale the moment the reader changes server.
  String? imageFor(String baseUrl) => resolveMediaUrl(imageUrl, baseUrl);

  String sectionLabel(String language) {
    if (language == 'en') {
      return sectionLabelEn ?? section.replaceAll('-', ' ');
    }
    return sectionLabelTe ?? sectionLabelEn ?? section;
  }

  /// Where the story happened, deepest level available.
  String? get place {
    if (mandal != null && mandal!.isNotEmpty) return mandal;
    if (district != null && district!.isNotEmpty) return district;
    if (state != null && state!.isNotEmpty) return state;
    return null;
  }

  bool get isHeld => status == 'held';
  bool get isKilled => status == 'killed';
  bool get isCorrected => correctionsCount > 0 || status == 'corrected';

  /// True when at least two independent outlets reported it.
  bool get isCorroborated => numSources >= 2;

  /// True when the sources disagree on something material. The newsroom
  /// never hides this; the app shows it as prominently as the corroboration
  /// badge.
  bool get hasConflict => sources.any((s) => (s.conflictsWith ?? '').isNotEmpty);

  factory Story.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? value) {
      if (value == null) return null;
      final parsed = DateTime.tryParse(value.toString());
      return parsed?.toUtc().toLocal();
    }

    return Story(
      id: json['id'] as int,
      clusterId: json['cluster_id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      section: json['section'] as String? ?? 'telangana',
      status: json['status'] as String? ?? 'published',
      importance: (json['importance'] as num?)?.toDouble() ?? 0.0,
      evidenceScore: (json['evidence_score'] as num?)?.toDouble() ?? 0.0,
      numSources: json['num_sources'] as int? ?? 0,
      isBreaking: json['is_breaking'] as bool? ?? false,
      isDeveloping: json['is_developing'] as bool? ?? false,
      headlineTe: json['headline_te'] as String?,
      headlineTen: json['headline_ten'] as String?,
      headlineEn: json['headline_en'] as String?,
      leadTe: json['lead_te'] as String?,
      sectionLabelTe: json['section_label_te'] as String?,
      sectionLabelEn: json['section_label_en'] as String?,
      statusLabelTe: json['status_label_te'] as String?,
      district: json['district'] as String?,
      mandal: json['mandal'] as String?,
      state: json['state'] as String?,
      imageUrl: json['image_url'] as String?,
      audioUrl: json['audio_url'] as String?,
      hasAudio: json['has_audio'] as bool? ?? false,
      publishedAt: parse(json['published_at']),
      updatedAt: parse(json['updated_at']),
      bodyTe: json['body_te'] as String?,
      bodyTen: json['body_ten'] as String?,
      bodyEn: json['body_en'] as String?,
      facts: (json['facts'] as List<dynamic>? ?? [])
          .map((e) => Fact.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      updates: (json['updates'] as List<dynamic>? ?? [])
          .map((e) => StoryUpdate.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      correctionsCount: json['corrections_count'] as int? ?? 0,
      version: json['version'] as int? ?? 1,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cluster_id': clusterId,
        'slug': slug,
        'section': section,
        'status': status,
        'importance': importance,
        'evidence_score': evidenceScore,
        'num_sources': numSources,
        'is_breaking': isBreaking,
        'is_developing': isDeveloping,
        'headline_te': headlineTe,
        'headline_ten': headlineTen,
        'headline_en': headlineEn,
        'body_te': bodyTe,
        'body_ten': bodyTen,
        'body_en': bodyEn,
        'district': district,
        'mandal': mandal,
        'state': state,
        'image_url': imageUrl,
        'audio_url': audioUrl,
        'has_audio': hasAudio,
        'published_at': publishedAt?.toIso8601String(),
      };

  Story copyWithDetail(Story other) {
    return Story(
      id: id,
      clusterId: other.clusterId,
      slug: other.slug,
      section: other.section,
      status: other.status,
      importance: other.importance,
      evidenceScore: other.evidenceScore,
      numSources: other.numSources,
      isBreaking: other.isBreaking,
      isDeveloping: other.isDeveloping,
      headlineTe: other.headlineTe ?? headlineTe,
      headlineTen: other.headlineTen ?? headlineTen,
      headlineEn: other.headlineEn ?? headlineEn,
      leadTe: other.leadTe ?? leadTe,
      sectionLabelTe: other.sectionLabelTe ?? sectionLabelTe,
      sectionLabelEn: other.sectionLabelEn ?? sectionLabelEn,
      statusLabelTe: other.statusLabelTe ?? statusLabelTe,
      district: other.district ?? district,
      mandal: other.mandal ?? mandal,
      state: other.state ?? state,
      imageUrl: other.imageUrl ?? imageUrl,
      audioUrl: other.audioUrl ?? audioUrl,
      hasAudio: other.hasAudio || hasAudio,
      publishedAt: other.publishedAt ?? publishedAt,
      updatedAt: other.updatedAt ?? updatedAt,
      bodyTe: other.bodyTe ?? bodyTe,
      bodyTen: other.bodyTen ?? bodyTen,
      bodyEn: other.bodyEn ?? bodyEn,
      facts: other.facts,
      sources: other.sources,
      updates: other.updates,
      correctionsCount: other.correctionsCount,
      version: other.version,
      confidence: other.confidence,
    );
  }

  @override
  bool operator ==(Object other) => other is Story && other.id == id;

  @override
  int get hashCode => id;

  /// The story needs a Telugu-aware line height only if its chosen headline
  /// actually carries the script.
  bool headlineIsTelugu(String language) => hasTeluguScript(headline(language));
}

/// One claim inside a story, with its evidence level attached.
///
/// The level is the newsroom's own taxonomy and must never be softened by the
/// app: an allegation stays an allegation all the way to the reader's screen.
class Fact {
  const Fact({
    required this.id,
    required this.textTe,
    required this.evidenceLevel,
    required this.confidence,
    this.textEn,
    this.evidenceLabelTe,
    this.evidenceLabelEn,
    this.attributedTo,
    required this.status,
    required this.rank,
  });

  final int id;
  final String textTe;
  final String? textEn;
  final String evidenceLevel;
  final String? evidenceLabelTe;
  final String? evidenceLabelEn;
  final double confidence;
  final String? attributedTo;
  final String status;
  final int rank;

  String text(String language) {
    final forEnglish = language == 'en';
    final chosen = (forEnglish && textEn?.isNotEmpty == true) ? textEn : textTe;
    return (chosen ?? '').trim();
  }

  String label(String language) {
    if (language == 'en') {
      return evidenceLabelEn ?? evidenceLevel.toUpperCase();
    }
    return evidenceLabelTe ?? evidenceLevel;
  }

  factory Fact.fromJson(Map<String, dynamic> json) => Fact(
        id: json['id'] as int,
        textTe: json['text_te'] as String? ?? '',
        textEn: json['text_en'] as String?,
        evidenceLevel: json['evidence_level'] as String? ?? 'claim',
        evidenceLabelTe: json['evidence_label_te'] as String?,
        evidenceLabelEn: json['evidence_label_en'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        attributedTo: json['attributed_to'] as String?,
        status: json['status'] as String? ?? 'active',
        rank: json['rank'] as int? ?? 0,
      );

  bool get isFactual =>
      evidenceLevel == 'fact' || evidenceLevel == 'official';

  bool get isWeakest =>
      evidenceLevel == 'allegation' ||
      evidenceLevel == 'unverified' ||
      evidenceLevel == 'disputed';
}

/// A link back to the outlet that reported the story.
class SourceLink {
  const SourceLink({
    required this.id,
    required this.corroborates,
    this.sourceName,
    this.siteUrl,
    this.articleUrl,
    this.articleTitle,
    this.publishedAt,
    this.conflictsWith,
  });

  final int id;
  final String? sourceName;
  final String? siteUrl;
  final String? articleUrl;
  final String? articleTitle;
  final DateTime? publishedAt;
  final bool corroborates;
  final String? conflictsWith;

  String get displayUrl {
    final raw = articleUrl ?? siteUrl ?? '';
    return raw.replaceAll(RegExp(r'^https?://(www\.)?'), '').split('/')[0];
  }

  factory SourceLink.fromJson(Map<String, dynamic> json) => SourceLink(
        id: json['id'] as int,
        sourceName: json['source_name'] as String?,
        siteUrl: json['site_url'] as String?,
        articleUrl: json['article_url'] as String?,
        articleTitle: json['article_title'] as String?,
        publishedAt: json['published_at'] == null
            ? null
            : DateTime.tryParse(json['published_at'].toString())?.toLocal(),
        corroborates: json['corroborates'] as bool? ?? false,
        conflictsWith: json['conflicts_with'] as String?,
      );
}

/// A later correction or update appended to a published story.
class StoryUpdate {
  const StoryUpdate({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.headline,
    this.textTe,
    this.textEn,
    this.appliedBy,
  });

  final int id;
  final String kind;
  final String? headline;
  final String? textTe;
  final String? textEn;
  final DateTime createdAt;
  final String? appliedBy;

  bool get isCorrection => kind == 'correction';

  String text(String language) {
    if (language == 'en') {
      return (textEn?.isNotEmpty == true ? textEn : textTe) ?? '';
    }
    return textTe ?? '';
  }

  factory StoryUpdate.fromJson(Map<String, dynamic> json) => StoryUpdate(
        id: json['id'] as int,
        kind: json['kind'] as String? ?? 'update',
        headline: json['headline'] as String?,
        textTe: json['text_te'] as String?,
        textEn: json['text_en'] as String?,
        createdAt:
            DateTime.tryParse((json['created_at'] ?? '').toString()) ??
                DateTime.now(),
        appliedBy: json['applied_by'] as String?,
      );
}
