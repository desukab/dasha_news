import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_strings.dart';
import '../../core/error_message.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/front_page.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../widgets/masthead.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// The front page.
///
/// The page is four questions over the same published room — what is happening
/// now, what is happening near the reader, what is happening in Telangana, and
/// what is happening beyond it — and the newsroom answers all four in one
/// request. The app's contribution is the asking: the masthead, the order the
/// regions are scanned in, and the district the Near You region is filed
/// against.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends TabPageState<HomePage> {
  final ScrollController _controller = ScrollController();

  /// The developing rail has its own repository and page list, because it is a
  /// separate endpoint and must fail on its own: a dead `/v1/developing` must
  /// never take the front page down with it.
  late final FeedRepository _developingRepository;
  late final PagedList _developing;

  /// The front page the newsroom last sent, or `null` while the first request
  /// is still in flight. Held as a plain value rather than a [PagedList]
  /// because the front page is not paginated: it is one bounded answer to four
  /// questions, and a reader who wants more goes to Latest or to a section.
  FrontPage? _front;
  String? _district;
  String? _lastLocale;
  bool _bootstrapped = false;
  bool _servingCache = false;
  ApiException? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final stored = app.storage.homeDistrict;
    _district = stored.isEmpty ? null : stored;
    _lastLocale = app.locale;
    _developingRepository = FeedRepository(app, CacheNames.developing);
    _developing = PagedList((page) => _developingRepository.fetch(
          load: () => app.api.developing(page: page, pageSize: 6),
        ));
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // The cached front renders instantly; the real fetch replaces it.
    final cached = await _readCachedFront();
    if (cached != null && !cached.isEmpty && mounted) {
      setState(() {
        _front = cached;
        _servingCache = true;
      });
    }
    await _load();
    // The rail is a nicety: it is fetched after the page, so a slow newsroom
    // shows the reader the front page first and fills the rail in after.
    if (mounted) await _developing.refresh();
    if (!mounted) return;
    final app = context.read<AppState>();
    if (_servingCache && _error != null && (_error as ApiException).isOffline) {
      // The network failed but the cache is showing; leave it up.
    } else {
      _servingCache = false;
    }
    _lastLocale = app.locale;
    setState(() => _bootstrapped = true);
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      final front = await app.api.front(
        language: app.locale,
        district: _district,
      );
      if (!mounted) return;
      setState(() {
        _front = front;
        _error = null;
      });
      await _persistFront(front);
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() => _error = exc);
      // A cold start that cannot reach the newsroom keeps whatever the cache
      // has; only a cache that is empty too becomes the retry screen.
      if (exc.isOffline || exc.kind == ApiFailure.network) {
        final cached = await _readCachedFront();
        if (cached != null && !cached.isEmpty && mounted) {
          setState(() => _front = cached);
        }
      }
    }
  }

  /// The cached front page, or `null`. A stale-language cache is a miss rather
  /// than an answer in the wrong script, the same rule the feed's repository
  /// applies.
  Future<FrontPage?> _readCachedFront() async {
    try {
      final app = context.read<AppState>();
      final raw = await app.storage.getCache(CacheNames.front);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      // A cached front is only reusable in the language it was fetched in; a
      // stale-language cache is a miss, not an answer in the wrong script.
      if (decoded['language'] is! String || decoded['language'] != app.locale) {
        return null;
      }
      return FrontPage.fromJson(decoded);
    } on Exception {
      // A corrupt cache is discarded, not shown.
      return null;
    }
  }

  Future<void> _persistFront(FrontPage front) async {
    if (front.isEmpty) return;
    final app = context.read<AppState>();
    await app.storage.putCache(
      CacheNames.front,
      jsonEncode({..._frontJson(front), 'language': app.locale}),
    );
  }

  Map<String, dynamic> _frontJson(FrontPage front) => {
        'now': _regionJson(front.now),
        'near': _regionJson(front.near),
        'telangana': _regionJson(front.telangana),
        'india_world': _regionJson(front.indiaWorld),
        'language': front.language,
        'district': front.district,
      };

  Map<String, dynamic> _regionJson(Region region) => {
        'items': region.items.map((story) => story.toJson()).toList(),
        'total': region.total,
        'asked': region.asked,
        'has_more': region.hasMore,
      };

  void _onScroll() {
    // The front page is one bounded answer, so there is nothing to page in.
    // The controller stays because scroll-to-top and the developing rail both
    // depend on it.
  }

  @override
  void jumpToTop() {
    if (_controller.hasClients) {
      _controller.animateTo(0,
          duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_bootstrapped && _lastLocale != app.locale) {
      _lastLocale = app.locale;
      _load();
      _developing.refresh();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _developing.dispose();
    super.dispose();
  }

  void _openStory(Story story) {
    context.read<HistoryRecorder>().start(story.id);
    Navigator.pushNamed(context, DashaRouter.story,
        arguments: StoryDetailArgs(story: story));
  }

  void _setDistrict(String? value) {
    final app = context.read<AppState>();
    app.storage.setString(homeDistrictKey, value ?? '');
    setState(() => _district = value);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return TabScaffold(
      // The front page carries its own masthead band, so the app bar shows the
      // mark alone; the nameplate is not repeated twice above the same page.
      title: app.strings.home,
      titleWidget: const DashaMonogram(extent: 32),
      body: AnimatedBuilder(
        animation: _developing,
        builder: (context, _) => _body(context, app.strings),
      ),
    );
  }

  Widget _body(BuildContext context, AppStrings strings) {
    final front = _front;
    // Nothing has arrived at all: the newsroom was unreachable and the cache
    // had nothing. This is the retry screen's condition, and it is distinct
    // from a region being empty, which is a prompt, not a failure.
    if (front == null && _error != null) {
      return ErrorState(
        message: errorMessage(strings, _error),
        onRetry: () => _load(),
      );
    }
    if (front == null) return const LoadingView();
    if (front.isEmpty) {
      return EmptyState(
        title: strings.feedEmpty,
        hint: strings.feedEmptyHint,
        actionLabel: strings.retry,
        onAction: () => _load(),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: 110),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _itemCount,
        itemBuilder: (context, index) => _item(context, index, strings),
      ),
    );
  }

  // -- the page, slot by slot ------------------------------------------------

  /// The regions actually being drawn, in scan order, with the Near You region
  /// last among the empty ones so a reader without a district meets the prompt
  /// rather than a gap mid-page.
  List<_RegionSpec> get _specs {
    final strings = context.read<AppState>().strings;
    final front = _front;
    if (front == null) return const [];
    return [
      _RegionSpec(front.now, strings.regionNow),
      _RegionSpec(front.near, strings.regionNear,
          isNear: true, onChooseDistrict: () => _chooseDistrict(
              context, context.read<AppState>(), strings)),
      _RegionSpec(front.telangana, strings.regionTelangana),
      _RegionSpec(front.indiaWorld, strings.regionIndiaWorld),
    ];
  }

  /// Slots, in order: the masthead, the developing rail (when it has stories),
  /// then for each region a header slot followed by one slot per story, then
  /// the footer. A region with no stories still costs a slot when it has
  /// something to say — the Near You prompt — and none when it does not.
  int get _itemCount {
    final n = _listStories;
    return 1 +
        (_developing.items.isNotEmpty ? 1 : 0) +
        n +
        1;
  }

  /// Every story slot across all drawn regions, in order.
  int get _listStories {
    var count = 0;
    for (final spec in _specs) {
      if (spec.region.isEmpty && !spec.isNear) continue;
      count += 1; // the header
      count += spec.region.items.length; // the stories
      if (spec.isNear && spec.region.isEmpty) count += 1; // the district prompt
    }
    return count;
  }

  Widget _item(BuildContext context, int index, AppStrings strings) {
    final specs = _specs;
    final hasRail = _developing.items.isNotEmpty;

    if (index == 0) return _masthead(context, strings);
    var slot = index - 1;
    if (hasRail) {
      if (slot == 0) return _DevelopingRail(stories: _developing.items);
      slot -= 1;
    }

    // Walk the regions, consuming slots until the asked one is reached.
    for (final spec in specs) {
      final drawsHeader = spec.region.isNotEmpty || spec.isNear;
      if (!drawsHeader) continue;
      if (slot == 0) return _RegionHeader(spec: spec);
      slot -= 1;
      final stories = spec.region.items;
      if (slot < stories.length) {
        return _regionStory(context, spec, stories[slot]);
      }
      slot -= stories.length;
      if (spec.isNear && spec.region.isEmpty) {
        if (slot == 0) return _nearPrompt(context, strings);
        slot -= 1;
      }
    }
    return _footer(context, strings);
  }

  /// The first story of the Now region is the front page's lead — full-bleed,
  /// with the photograph — and every other story in every region is a brief.
  Widget _regionStory(
      BuildContext context, _RegionSpec spec, Story story) {
    final isLead = identical(spec.region, _front!.now) &&
        identical(story, _front!.now.items.first);
    if (isLead) {
      return _inset(
        StoryCard(
          story: story,
          variant: StoryVariant.lead,
          heroTag: _photoHeroTag(story),
          onTap: () => _openStory(story),
        ),
        vertical: 14,
      );
    }
    return _inset(
      StoryCard(
        story: story,
        variant: StoryVariant.brief,
        onTap: () => _openStory(story),
      ),
      horizontal: 14,
      vertical: 0,
    );
  }

  /// What the reader sees when Near You has no district to file against: not an
  /// empty region hidden away, but the question itself, one tap from being
  /// answered.
  Widget _nearPrompt(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    return _inset(
      Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _chooseDistrict(context, context.read<AppState>(),
              strings),
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.place_rounded, size: 18,
                    color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.nearNeedsDistrict,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        strings.nearNeedsDistrictHint,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
      horizontal: 14,
      vertical: 0,
    );
  }

  Widget _inset(Widget child, {double horizontal = 14, double vertical = 0}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
      child: child,
    );
  }

  /// The hero tag a card's photograph and the story page's photograph share.
  /// Only the lead and the secondary pair carry one: the briefs have no
  /// photograph, and the developing rail draws the same stories the feed does,
  /// so tagging its thumbnails would put two heroes on one screen.
  String _photoHeroTag(Story story) => 'story-photo-${story.id}';

  /// The nameplate band: the paper's name, the edition date, and the district
  /// the reader has chosen, which is one tap away rather than a pill bar of
  /// thirty-three.
  Widget _masthead(BuildContext context, AppStrings strings) {
    final app = context.watch<AppState>();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [mastheadRed, mastheadRedDark],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Center(child: DashaMasthead(size: MastheadSize.front)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: MastheadFolio(date: _dateLine(strings)),
              ),
              _districtChip(context, app, strings),
            ],
          ),
        ],
      ),
    );
  }

  /// "శుక్రవారం, 19 సెప్టెంబరు" in Telugu, or the English long form; the
  /// edition line a front page carries under its name.
  ///
  /// Formatted off the English names and translated here rather than handed to
  /// `intl` with a Telugu locale, because Telugu locale data is not loaded
  /// unless the app initialises it explicitly. [formatIndianDate] carries the
  /// same reasoning one step further: even the English data failing to load
  /// yields a plain date rather than no front page at all.
  String _dateLine(AppStrings strings) {
    final english =
        formatIndianDate('EEEE, d MMMM y', DateTime.now()).split(', ');
    final weekday = english.first;
    final rest = english.last.split(' ');
    if (strings.code != 'te') return english.join(', ');
    final teWeekday = _teWeekdays[weekday] ?? weekday;
    final teMonth = _teMonths[rest[1]] ?? rest[1];
    return '$teWeekday, ${rest[0]} $teMonth ${rest[2]}';
  }

  Widget _districtChip(
      BuildContext context, AppState app, AppStrings strings) {
    final label = _district ?? strings.stateEdition;
    return Material(
      color: mastheadChip,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _chooseDistrict(context, app, strings),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.place_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  void _chooseDistrict(BuildContext context, AppState app, AppStrings strings) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(strings.chooseDistrict,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  RadioGroup<String>(
                    groupValue: _district ?? '',
                    onChanged: (value) {
                      Navigator.pop(sheetContext);
                      _setDistrict(value?.isEmpty == true ? null : value);
                    },
                    child: Column(
                      children: [
                        RadioListTile<String>(
                          value: '',
                          title: Text(strings.allDistricts),
                        ),
                        for (final name in app.districts)
                          RadioListTile<String>(
                            value: name,
                            title: Text(name),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What sits under the last story: the offline note when only the cache is
  /// being served, and nothing but a rule when the page has ended.
  Widget _footer(BuildContext context, AppStrings strings) {
    if (_servingCache) return _offlineBanner(context, strings);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Center(
        child: Container(
          width: 44,
          height: 2,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }

  Widget _offlineBanner(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 16, color: theme.colorScheme.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                strings.offlineHint,
                style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The developing rail: a horizontal strip of the stories the newsroom is
/// still reporting, under a `కొనసాగుతున్న` header.
///
/// It is drawn as a strip because these are stories without endings yet — the
/// reader scans them sideways, the way a tickertape moves.
class _DevelopingRail extends StatelessWidget {
  const _DevelopingRail({required this.stories});

  final List<Story> stories;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.autorenew_rounded,
                    size: 15, color: SemanticColour.developing.inkOf(context)),
                const SizedBox(width: 6),
                Text(
                  strings.developing,
                  style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: SemanticColour.developing.inkOf(context),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: stories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final story = stories[index];
                return _RailCard(
                  story: story,
                  language: app.locale,
                  strings: strings,
                  onTap: () {
                    context.read<HistoryRecorder>().start(story.id);
                    Navigator.pushNamed(context, DashaRouter.story,
                        arguments: StoryDetailArgs(story: story));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.story,
    required this.language,
    required this.strings,
    required this.onTap,
  });

  final Story story;
  final String language;
  final AppStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (story.isBreaking)
                      _Dot(
                          colour: SemanticColour.breaking,
                          label: strings.breaking)
                    else
                      _Dot(
                          colour: SemanticColour.developing,
                          label: strings.developing),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Text(
                    story.headline(language),
                    style: storyHeadline(context, story.headline(language),
                            size: 14, maxLines: 4)
                        .copyWith(fontWeight: FontWeight.w700),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  relativeTime(story.publishedAt, strings: strings),
                  style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour, required this.label});

  final SemanticColour colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.badge,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 9.5,
              height: 1.35,
            ),
      ),
    );
  }
}

/// Telugu weekday names, keyed off the English `intl` produces.
const Map<String, String> _teWeekdays = {
  'Monday': 'సోమవారం',
  'Tuesday': 'మంగళవారం',
  'Wednesday': 'బుధవారం',
  'Thursday': 'గురువారం',
  'Friday': 'శుక్రవారం',
  'Saturday': 'శనివారం',
  'Sunday': 'ఆదివారం',
};

/// Telugu month names, in the same keying scheme.
const Map<String, String> _teMonths = {
  'January': 'జనవరి',
  'February': 'ఫిబ్రవరి',
  'March': 'మార్చి',
  'April': 'ఏప్రిల్',
  'May': 'మే',
  'June': 'జూన్',
  'July': 'జూలై',
  'August': 'ఆగస్టు',
  'September': 'సెప్టెంబరు',
  'October': 'అక్టోబరు',
  'November': 'నవంబరు',
  'December': 'డిసెంబరు',
};

/// One region of the front page, as the page draws it.
///
/// A region is its stories plus the label the reader scans the page by. The
/// Near You region is special only in that an empty one is still drawn — it
/// carries a prompt rather than a gap — so the reader can see that the
/// question was asked and unanswered, instead of the region quietly
/// disappearing.
class _RegionSpec {
  const _RegionSpec(this.region, this.label,
      {this.isNear = false, this.onChooseDistrict});

  final Region region;
  final String label;
  final bool isNear;

  /// Shown by the Near You prompt when the region is empty. Not a callback on
  /// the header itself: the header's job is to name the region, not to act.
  final VoidCallback? onChooseDistrict;
}

/// A region's name and the count the newsroom vouches for.
///
/// The count is the stories that exist, not the stories drawn: a region that
/// holds twelve and shows six says twelve, which is the honest answer to "is
/// there more here". A region that holds nothing shows no count at all, because
/// a zero would read as a claim that nothing is happening when what is true is
/// that the newsroom has not filed it.
class _RegionHeader extends StatelessWidget {
  const _RegionHeader({required this.spec});

  final _RegionSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final region = spec.region;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              color: spec.isNear
                  ? SemanticColour.developing.inkOf(context)
                  : mastheadRed,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            spec.label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
          if (region.total > 0) ...[
            const SizedBox(width: 7),
            Text(
              '${region.total}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (region.hasMore) ...[
            const SizedBox(width: 6),
            Text(
              context.read<AppState>().strings.latest,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
