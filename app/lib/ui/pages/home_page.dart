import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/config.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// The front page.
///
/// Ordering here is the newsroom's editorial judgement, not the app's: the
/// feed arrives sorted by importance with breaking stories promoted. The
/// app's only contribution is the district filter the reader applies on top.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends TabPageState<HomePage> {
  final ScrollController _controller = ScrollController();
  late final FeedRepository _repository;
  late final PagedList _list;
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
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _list.dispose();
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
      title: app.strings.appName,
      body: Column(
        children: [
          _districtBar(context, app),
          Expanded(child: _body(context, app.strings)),
        ],
      ),
    );
  }

  Widget _districtBar(BuildContext context, AppState app) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _pill(
            context: context,
            label: app.strings.stateEdition,
            selected: _district == null,
            onTap: () => _setDistrict(null),
          ),
          for (final name in app.districts)
            _pill(
              context: context,
              label: name,
              selected: _district == name,
              onTap: () => _setDistrict(name),
            ),
        ],
      ),
    );
  }

  Widget _pill({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppStrings strings) {
    return AnimatedBuilder(
      animation: _list,
      builder: (context, _) {
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
          child: ListView.separated(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _list.items.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              if (index == _list.items.length) {
                if (_servingCache) {
                  return _offlineBanner(context, strings);
                }
                if (!_list.hasMore) {
                  return const SizedBox.shrink();
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
              final story = _list.items[index];
              return StoryCard(
                story: story,
                onTap: () => _openStory(story),
                compact: index > 0,
              );
            },
          ),
        );
      },
    );
  }

  Widget _offlineBanner(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
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
