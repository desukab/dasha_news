import 'story.dart';

/// One page of a paginated newsroom response.
class StoryPage {
  const StoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.fromCache = false,
  });

  final List<Story> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;
  final bool fromCache;

  factory StoryPage.fromJson(Map<String, dynamic> json) => StoryPage(
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        total: json['total'] as int? ?? 0,
        page: json['page'] as int? ?? 1,
        pageSize: json['page_size'] as int? ?? 20,
        hasMore: json['has_more'] as bool? ?? false,
      );

  static StoryPage empty() => const StoryPage(
        items: [],
        total: 0,
        page: 1,
        pageSize: 20,
        hasMore: false,
      );

  StoryPage copyWith({List<Story>? items, bool? fromCache}) => StoryPage(
        items: items ?? this.items,
        total: total,
        page: page,
        pageSize: pageSize,
        hasMore: hasMore,
        fromCache: fromCache ?? this.fromCache,
      );
}

/// A newsroom section, with its labels in all three languages.
class NewsSection {
  const NewsSection({
    required this.slug,
    required this.te,
    required this.ten,
    required this.en,
    this.sensitive = false,
    this.telanganaLocal = false,
  });

  final String slug;
  final String te;
  final String ten;
  final String en;
  final bool sensitive;
  final bool telanganaLocal;

  String label(String language) {
    switch (language) {
      case 'ten':
        return ten;
      case 'en':
        return en;
      default:
        return te;
    }
  }

  factory NewsSection.fromJson(Map<String, dynamic> json) => NewsSection(
        slug: json['slug'] as String,
        te: (json['te'] as String?) ?? (json['slug'] as String),
        ten: (json['ten'] as String?) ?? (json['slug'] as String),
        en: (json['en'] as String?) ?? (json['slug'] as String),
        sensitive: json['sensitive'] as bool? ?? false,
        telanganaLocal: json['telangana_local'] as bool? ?? false,
      );
}

class SectionCatalogue {
  const SectionCatalogue({this.primary = const [], this.all = const []});

  final List<NewsSection> primary;
  final List<NewsSection> all;

  factory SectionCatalogue.fromJson(Map<String, dynamic> json) =>
      SectionCatalogue(
        primary: (json['primary'] as List<dynamic>? ?? [])
            .map((e) => NewsSection.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        all: (json['all'] as List<dynamic>? ?? [])
            .map((e) => NewsSection.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );

  NewsSection? bySlug(String slug) {
    for (final s in all) {
      if (s.slug == slug) return s;
    }
    return null;
  }
}

/// Reader preferences as the newsroom stores them.
class DeviceProfile {
  const DeviceProfile({
    required this.deviceId,
    required this.locale,
    required this.theme,
    required this.breakingAlerts,
    required this.dailyDigest,
  });

  final String deviceId;
  final String locale;
  final String theme;
  final bool breakingAlerts;
  final bool dailyDigest;

  factory DeviceProfile.fromJson(Map<String, dynamic> json) => DeviceProfile(
        deviceId: json['device_id'] as String,
        locale: json['locale'] as String? ?? 'te',
        theme: json['theme'] as String? ?? 'system',
        breakingAlerts: json['breaking_alerts'] as bool? ?? true,
        dailyDigest: json['daily_digest'] as bool? ?? false,
      );
}
