import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
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
/// Ordering here is the newsroom's editorial judgement, not the app's: the
/// feed arrives sorted by importance with breaking stories promoted. The
/// app's contribution is the page itself — the masthead, the lead story, the
/// developing rail, and the briefs underneath — and the district filter the
/// reader applies on top of it.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends TabPageState<HomePage> {
  final ScrollController _controller = ScrollController();
  late final FeedRepository _repository;
  late final PagedList _list;

  /// The developing rail has its own repository and page list, because it is a
  /// separate endpoint and must fail on its own: a dead `/v1/developing` must
  /// never take the front page down with it.
  late final FeedRepository _developingRepository;
  late final PagedList _developing;

  String? _district;
  String? _lastLocale;
  bool _bootstrapped = false;
  bool _servingCache = false;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _repository = FeedRepository(app, CacheNames.feed);
    final stored = app.storage.homeDistrict;
    _district = stored.isEmpty ? null : stored;
    _lastLocale = app.locale;
    _list = PagedList((page) => _repository.fetch(
          load: () => app.api.feed(
            language: app.locale,
            district: _district,
            page: page,
          ),
        ));
    _developingRepository = FeedRepository(app, CacheNames.developing);
    _developing = PagedList((page) => _developingRepository.fetch(
          load: () => app.api.developing(page: page, pageSize: 6),
        ));
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Cached pages render instantly; the real fetch replaces them.
    final cached = await _repository.lastGood();
    if (cached != null && cached.items.isNotEmpty && mounted) {
      _servingCache = true;
      await _list.injectCached(cached);
    }
    await _list.refresh();
    // The rail is a nicety: it is fetched after the page, so a slow newsroom
    // shows the reader the front page first and fills the rail in after.
    if (mounted) await _developing.refresh();
    if (!mounted) return;
    final app = context.read<AppState>();
    if (_servingCache && _list.error != null && _list.error!.isOffline) {
      // The network failed but the cache is showing; leave it up.
    } else {
      _servingCache = false;
    }
    _lastLocale = app.locale;
    setState(() => _bootstrapped = true);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels > position.maxScrollExtent - 480) {
      _list.loadMore();
    }
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
      _list.refresh();
      _developing.refresh();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _list.dispose();
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
    _list.refresh();
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
        animation: Listenable.merge([_list, _developing]),
        builder: (context, _) => _body(context, app.strings),
      ),
    );
  }

  Widget _body(BuildContext context, AppStrings strings) {
    if (_list.isLoading && _list.items.isEmpty) {
      return const LoadingView();
    }
    if (_list.isHardEmpty) {
      return ErrorState(
        message: _list.error?.message ?? strings.errorGeneric,
        onRetry: () => _list.refresh(),
      );
    }
    if (_list.isEmpty) {
      return EmptyState(
        title: strings.feedEmpty,
        hint: strings.feedEmptyHint,
        actionLabel: strings.retry,
        onAction: () => _list.refresh(),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _list.refresh(),
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

  /// Slots, in order: the masthead, the developing rail (when it has stories),
  /// the lead, the secondary pair, then one slot per remaining brief, then the
  /// footer the pagination spinner lives in.
  int get _itemCount {
    final n = _list.items.length;
    final briefs = n <= 3 ? 0 : n - 3;
    return 1 +
        (_developing.items.isNotEmpty ? 1 : 0) +
        (n == 0 ? 0 : 1) +
        (n >= 2 ? 1 : 0) +
        briefs +
        1;
  }

  Widget _item(BuildContext context, int index, AppStrings strings) {
    final items = _list.items;
    final n = items.length;
    final hasRail = _developing.items.isNotEmpty;

    if (index == 0) return _masthead(context, strings);
    var slot = index - 1;
    if (hasRail) {
      if (slot == 0) return _DevelopingRail(stories: _developing.items);
      slot -= 1;
    }
    if (slot == _storySlotCount(n)) return _footer(context, strings);

    if (slot == 0) {
      return _inset(
        StoryCard(
          story: items.first,
          variant: StoryVariant.lead,
          heroTag: _photoHeroTag(items.first),
          onTap: () => _openStory(items.first),
        ),
        vertical: 14,
      );
    }
    if (n == 1) return const SizedBox.shrink();
    if (slot == 1) {
      return _inset(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StoryCard(
                  story: items[1],
                  variant: StoryVariant.secondary,
                  heroTag: _photoHeroTag(items[1]),
                  onTap: () => _openStory(items[1]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: n >= 3
                    ? StoryCard(
                        story: items[2],
                        variant: StoryVariant.secondary,
                        heroTag: _photoHeroTag(items[2]),
                        onTap: () => _openStory(items[2]),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        vertical: 14,
      );
    }
    final storyIndex = 3 + (slot - 2);
    if (storyIndex >= n) return const SizedBox.shrink();
    final story = items[storyIndex];
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

  /// Lead, plus the secondary pair, plus one slot per brief.
  int _storySlotCount(int n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    return 2 + max(0, n - 3);
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
  /// being served, the pagination spinner when there is more to load, and
  /// nothing at all when the page has ended.
  Widget _footer(BuildContext context, AppStrings strings) {
    if (_servingCache) return _offlineBanner(context, strings);
    if (!_list.hasMore) {
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: _list.isLoadingMore
              ? const CircularProgressIndicator(strokeWidth: 2)
              : null,
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
