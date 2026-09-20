import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_strings.dart';
import '../../core/config.dart';
import '../../core/error_message.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/front_page.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../main_shell.dart';
import '../router.dart';
import '../widgets/masthead.dart';
import '../../widgets/states_view.dart';
import '../../widgets/swipe_story_view.dart';

/// The front page, as a short-news reader reads it: one story to a screen.
///
/// The page is four questions over the same published room — what is happening
/// now, what is happening near the reader, what is happening in Telangana, and
/// what is happening beyond it — and the newsroom answers all four in one
/// request. The app's contribution is the asking and the pace: the stream
/// flattens those four answers into one sequence the reader thumbs through,
/// and each screen carries the region it came from so a reader swiping through
/// twenty stories always knows which question they are inside.
///
/// A reader who wants the whole story taps the screen. A reader who wants the
/// next story swipes up. Nothing else is asked of them.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends TabPageState<HomePage> {
  /// The stream is walked with a page controller rather than a scroll
  /// controller, because a swipe reader's position is a story index, not a
  /// pixel offset: "go back to the top" means the first story, not scroll
  /// position zero.
  final PageController _controller = PageController();

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
    if (!mounted) return;
    _lastLocale = context.read<AppState>().locale;
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
        // The newsroom was reached, so what is on screen is no longer the
        // cache's copy. This is the only success path, and it is why a stream
        // that recovered stops describing itself as offline.
        _servingCache = false;
      });
      await _persistFront(front);
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() => _error = exc);
      // A start that cannot reach the newsroom keeps whatever the cache has;
      // only a cache that is empty too becomes the retry screen.
      if (exc.isOffline || exc.kind == ApiFailure.network) {
        final cached = await _readCachedFront();
        if (cached != null && !cached.isEmpty && mounted) {
          // What is on screen is the cache's copy, so the flag is set where
          // the copy is put up — the same rule as the fast path in
          // _bootstrap, rather than a second rule derived from the error.
          setState(() {
            _front = cached;
            _servingCache = true;
          });
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
    } catch (_) {
      // A corrupt cache is discarded, not shown. The catch is broad on
      // purpose: a malformed entry fails the JSON or the nested `as` casts
      // inside `fromJson` with a TypeError, which is not an Exception and so
      // slips an `on Exception` guard to the reader's screen.
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

  @override
  void jumpToTop() {
    if (_controller.hasClients) {
      _controller.animateToPage(0,
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
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
      // The stream's chrome carries the nameplate, the district the reader is
      // filed against, and the language switch — the three things a reader
      // needs before the first story, and nothing more. The submission affordance
      // moves to the end of the stream, so the floating button never lands on
      // the share action a story screen carries.
      title: app.strings.home,
      titleWidget: const DashaMasthead(
        size: MastheadSize.compact,
        onColour: false,
      ),
      actions: [
        _districtAction(context, app, app.strings),
        const LanguageButton(),
      ],
      showFab: false,
      body: _body(context, app.strings),
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
    return _stream(context, front, strings);
  }

  /// The stream itself: one screen per story, walked vertically.
  ///
  /// A region is allowed to be empty, and an empty Near You region is still
  /// drawn — as a screen that asks the question, one tap from being answered —
  /// so the reader can see the newsroom was asked, rather than the region
  /// silently vanishing from the stream.
  Widget _stream(BuildContext context, FrontPage front, AppStrings strings) {
    final screens = _screens(front, strings);
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          scrollDirection: Axis.vertical,
          itemCount: screens.length,
          itemBuilder: (context, index) => screens[index],
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _Progress(controller: _controller, count: screens.length),
        ),
      ],
    );
  }

  /// Every screen in the stream, in scan order: Now, Near You, Telangana, then
  /// India & World. Stories a region does not have are skipped; a Near You
  /// region with no district costs one screen, not zero, because the prompt is
  /// the region's answer.
  List<Widget> _screens(FrontPage front, AppStrings strings) {
    final screens = <Widget>[];
    void region(Region region, String label, {bool isNear = false}) {
      if (region.items.isEmpty) {
        if (isNear) {
          screens.add(_NearYouPrompt(
            label: label,
            onChoose: () =>
                _chooseDistrict(context, context.read<AppState>(), strings),
          ));
        }
        return;
      }
      for (final story in region.items) {
        screens.add(
          SwipeStoryView(
            story: story,
            regionLabel: label,
            heroTag: _photoHeroTag(story),
            onTap: () => _openStory(story),
          ),
        );
      }
    }

    region(front.now, strings.regionNow);
    region(front.near, strings.regionNear, isNear: true);
    region(front.telangana, strings.regionTelangana);
    region(front.indiaWorld, strings.regionIndiaWorld);

    // The two end notes differ only in what they tell the reader; the
    // masthead, the dateline, and the recovery gesture are the same screen.
    final (endIcon, endText) = _servingCache
        ? (Icons.wifi_off_rounded, strings.offlineHint)
        : (Icons.check_circle_outline_rounded, strings.streamEnd);
    screens.add(_EndNote(
      icon: endIcon,
      text: endText,
      dateLine: editionDateLine(strings),
      onRefresh: _load,
    ));
    return screens;
  }

  /// The hero tag a screen's photograph and the story page's photograph share.
  /// Exactly one screen is visible at a time, so every story may carry one —
  /// unlike a scrolling list, where the same story appearing twice would put
  /// two heroes on one screen.
  String _photoHeroTag(Story story) => 'story-photo-${story.id}';

  Widget _districtAction(
      BuildContext context, AppState app, AppStrings strings) {
    return IconButton(
      tooltip: strings.district,
      onPressed: () => _chooseDistrict(context, app, strings),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_rounded, size: 17),
          const SizedBox(width: 4),
          Text(
            _district ?? strings.stateEdition,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 16),
        ],
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
}

/// The progress bar: one segment per story, capped at a window of fourteen
/// that scrolls with the reader, read segments filled and the rest hollow.
///
/// A swipe reader's single hardest question is "how much is left". A scrollbar
/// answers it in pixels, which a stream of full screens does not have; a count
/// answers it in arithmetic, which the reader has to do. Segments answer it in
/// the same gesture the reader is already making.
class _Progress extends StatefulWidget {
  const _Progress({required this.controller, required this.count});

  final PageController controller;
  final int count;

  @override
  State<_Progress> createState() => _ProgressState();
}

class _ProgressState extends State<_Progress> {
  int _page = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPage);
  }

  void _onPage() {
    final page = widget.controller.page?.round() ?? 0;
    if (page != _page) setState(() => _page = page);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A stream is long; the segments stay legible by capping how many are
    // drawn and scrolling the window with the reader.
    final long = widget.count > 14;
    final visible = long ? 14 : widget.count;
    final start = long
        ? (_page - visible ~/ 4).clamp(0, widget.count - visible)
        : 0;
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              for (var i = 0; i < visible; i++)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    height: 2.4,
                    decoration: BoxDecoration(
                      color: (start + i) <= _page
                          ? mastheadRed
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the reader meets when Near You has no district to file against: not an
/// empty region skipped over, but the question itself, one tap from being
/// answered. It is a screen in the stream, because a gap the reader swipes
/// past is not an answer.
class _NearYouPrompt extends StatelessWidget {
  const _NearYouPrompt({required this.label, required this.onChoose});

  final String label;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.read<AppState>().strings;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 12),
            Icon(Icons.place_rounded,
                size: 40, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              strings.nearNeedsDistrict,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              strings.nearNeedsDistrictHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                onChoose();
              },
              icon: const Icon(Icons.place_rounded, size: 17),
              label: Text(strings.chooseDistrict),
            ),
          ],
        ),
      ),
    );
  }
}

/// The screen after the last story: the offline note when the stream is being
/// served from cache, a plain end mark when the newsroom was reached, and the
/// edition's dateline under both.
///
/// It is also where the tip line and the refresh live. A floating button on
/// every screen of a stream lands on the share action a story carries, so the
/// submission affordance moves here — where the reader has just run out of news
/// and is most likely to have something to say. The refresh is here for the
/// same reason: a stream has no scroll position to pull against, so the reader
/// who has been on the tab for an hour and wants the latest bulletin finds the
/// gesture at the end of the one they have, not by leaving the tab.
class _EndNote extends StatelessWidget {
  const _EndNote({
    required this.icon,
    required this.text,
    this.dateLine,
    required this.onRefresh,
  });

  final IconData icon;
  final String text;

  /// The edition line, when the stream has one to close with.
  final String? dateLine;

  /// Re-fetches the front page. Offered because the stream has no other
  /// gesture that reaches the newsroom again.
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.read<AppState>().strings;
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (dateLine != null) ...[
              const SizedBox(height: 6),
              Text(
                dateLine!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),
            const DashaMasthead(size: MastheadSize.compact, onColour: false),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                onRefresh();
              },
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: Text(strings.refreshStream),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                Navigator.pushNamed(context, DashaRouter.submitTip);
              },
              icon: const Icon(Icons.campaign_outlined, size: 17),
              label: Text(strings.submitTip),
            ),
          ],
        ),
      ),
    );
  }
}
