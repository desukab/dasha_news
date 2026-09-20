import 'story.dart';

/// The four regions of the front page, as the newsroom sends them in one
/// response.
///
/// Each region answers a different question over the same published room, so
/// the same story may appear in two -- the freshest Telangana story is also the
/// Telangana region's lead. That is a front page repeating itself, not a
/// failure to dedupe, and the app does not try to hide it.
///
/// A region is allowed to be empty. [Region.asked] is the question that went
/// unanswered, and the app shows it rather than silently dropping the slot:
/// Near You with no district is a prompt to choose one, not an absence.
class FrontPage {
  const FrontPage({
    required this.now,
    required this.near,
    required this.telangana,
    required this.indiaWorld,
    this.language = 'te',
    this.district,
  });

  final Region now;
  final Region near;
  final Region telangana;
  final Region indiaWorld;
  final String language;
  final String? district;

  /// Every region the front page draws, in the order the reader scans them.
  List<Region> get regions => [now, near, telangana, indiaWorld];

  factory FrontPage.fromJson(Map<String, dynamic> json) {
    Region read(String key) {
      final raw = json[key];
      return raw is Map<String, dynamic> ? Region.fromJson(raw) : const Region();
    }

    return FrontPage(
      now: read('now'),
      near: read('near'),
      telangana: read('telangana'),
      indiaWorld: read('india_world'),
      language: json['language'] as String? ?? 'te',
      district: json['district'] as String?,
    );
  }

  FrontPage copyWith({bool? fromCache}) => FrontPage(
        now: now,
        near: near,
        telangana: telangana,
        indiaWorld: indiaWorld,
        language: language,
        district: district,
      );

  /// True when not one region has a story. The front page's empty state is
  /// distinct from any single region's: it means the newsroom answered nothing
  /// at all, which is the retry screen's condition, not the district prompt's.
  bool get isEmpty =>
      now.items.isEmpty &&
      near.items.isEmpty &&
      telangana.items.isEmpty &&
      indiaWorld.items.isEmpty;
}

/// One region of the front page.
class Region {
  const Region({
    this.items = const [],
    this.total = 0,
    this.asked,
    this.hasMore = false,
  });

  final List<Story> items;
  final int total;

  /// The question this region answers: a district name for Near You, a desk
  /// slug otherwise. Carried to the reader because an empty region is only
  /// meaningful if it is visible which question went unanswered.
  final String? asked;
  final bool hasMore;

  bool get isEmpty => items.isEmpty;

  bool get isNotEmpty => items.isNotEmpty;

  factory Region.fromJson(Map<String, dynamic> json) => Region(
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => Story.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
        total: json['total'] as int? ?? 0,
        asked: json['asked'] as String?,
        hasMore: json['has_more'] as bool? ?? false,
      );
}
