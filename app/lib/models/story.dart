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
  });

  final int id;
  final String clusterId;
  final String slug;
  final String section;
  final String status;
  final double importance;
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

  /// The headline the reader asked for, in a language it is actually written
  /// in.
  ///
  /// A column name is not a guarantee: stories published before the
  /// newsroom's script gate landed still carry English wire copy in the
  /// Telugu column, and an offline cache can hold a copy from before the fix.
  /// So the field is only used when its script matches the language the reader
  /// asked for; otherwise the story falls back to a language it really is in,
  /// and the reader is never shown English under a Telugu label.
  String headline(String language) {
    final chosen = _languageField(language, headlineTe, headlineTen, headlineEn);
    if (chosen != null) return chosen;
    // None of the columns holds the asked-for language. Take whichever of the
    // others is genuinely written in something, preferring Telugu, then
    // Tenglish, then English -- a real headline in the wrong language beats a
    // blank line, and the slug is the last resort.
    for (final candidate in [headlineTe, headlineTen, headlineEn]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return slug.trim();
  }

  /// `value` for [language], but only when its script agrees.
  String? _languageField(
      String language, String? te, String? ten, String? en) {
    switch (language) {
      case 'ten':
        // Roman Telugu is Latin script, so the Telugu-script test cannot judge
        // it. The newsroom's shape check already withheld an English line from
        // this column; here a Telugu-script line is the only clear wrong.
        return (ten != null && ten.trim().isNotEmpty && !hasTeluguScript(ten))
            ? ten.trim()
            : null;
      case 'en':
        return (en != null && en.trim().isNotEmpty && !hasTeluguScript(en))
            ? en.trim()
            : null;
      default:
        return (te != null && te.trim().isNotEmpty && hasTeluguScript(te))
            ? te.trim()
            : null;
    }
  }

  /// Body for the chosen language, withheld the same way as the headline.
  String body(String language) {
    final chosen = _languageField(language, bodyTe, bodyTen, bodyEn);
    if (chosen != null) return chosen;
    for (final candidate in [bodyTe, bodyTen, bodyEn]) {
      if (candidate != null && candidate.trim().isNotEmpty) return candidate;
    }
    return '';
  }

  /// The story's lead, preferring a Telugu one that really is Telugu.
  String get lead {
    final te = leadTe;
    if (te != null && te.trim().isNotEmpty && hasTeluguScript(te)) return te;
    final firstSentence = body('te').split(RegExp(r'[।.]'))[0];
    return firstSentence.trim().isNotEmpty
        ? firstSentence.trim()
        : (leadTe ?? '').trim();
  }

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
  bool get isCorrected => status == 'corrected';

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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cluster_id': clusterId,
        'slug': slug,
        'section': section,
        'status': status,
        'importance': importance,
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

