import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/story.dart';
import '../../models/page.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// Sections and the developing rail.
///
/// The taxonomy comes from the newsroom, so a new vertical there appears here
/// without an app release. Until the catalogue loads, a small built-in set
/// keeps the screen from being empty.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends TabPageState<ExplorePage> {
  final ScrollController _controller = ScrollController();
  late final PagedList _developing;
  String? _section;
  late final PagedList _sectionList;
  String? _lastLocale;

  static const List<NewsSection> _fallbackSections = [
    NewsSection(slug: 'telangana', te: 'తెలంగాణ', ten: 'Telangana', en: 'Telangana'),
    NewsSection(slug: 'hyderabad', te: 'హైదరాబాద్', ten: 'Hyderabad', en: 'Hyderabad'),
    NewsSection(slug: 'politics', te: 'రాజకీయాలు', ten: 'Rajakeeyalu', en: 'Politics'),
    NewsSection(slug: 'district', te: 'జిల్లాలు', ten: 'Jillalu', en: 'Districts'),
    NewsSection(slug: 'crime', te: 'నేరాలు', ten: 'Nerulu', en: 'Crime'),
    NewsSection(slug: 'sports', te: 'క్రీడలు', ten: 'Kreedalu', en: 'Sports'),
    NewsSection(slug: 'cinema', te: 'సినిమా', ten: 'Sinema', en: 'Cinema'),
    NewsSection(slug: 'business', te: 'వ్యాపారం', ten: 'Vyaparam', en: 'Business'),
    NewsSection(slug: 'education', te: 'విద్య', ten: 'Vidya', en: 'Education'),
    NewsSection(slug: 'jobs', te: 'ఉద్యోగాలు', ten: 'Udyogalu', en: 'Jobs'),
    NewsSection(slug: 'health', te: 'ఆరోగ్యం', ten: 'Arogyam', en: 'Health'),
    NewsSection(slug: 'agriculture', te: 'వ్యవసాయం', ten: 'Vyavasayam', en: 'Agriculture'),
  ];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _lastLocale = app.locale;
    final repository = FeedRepository(app, CacheNames.developing);
    _developing = PagedList((page) => repository.fetch(
          load: () => app.api.developing(page: page),
        ));
    final sectionRepository = FeedRepository(app, CacheNames.feed);
    _sectionList = PagedList((page) => sectionRepository.fetch(
          load: () => app.api.feed(
            language: app.locale,
            section: _section,
            page: page,
          ),
        ));
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _developing.refresh());
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.pixels > position.maxScrollExtent - 480) {
      if (_section != null) {
        _sectionList.loadMore();
      } else {
        _developing.loadMore();
      }
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
    if (_lastLocale != app.locale) {
      _lastLocale = app.locale;
      _developing.refresh();
      _sectionList.refresh();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _developing.dispose();
    _sectionList.dispose();
    super.dispose();
  }

  void _openSection(String slug) {
    setState(() => _section = slug);
    _sectionList.refresh();
  }

  void _closeSection() {
    setState(() => _section = null);
  }

  void _openStory(Story story) {
    context.read<HistoryRecorder>().start(story.id);
    Navigator.pushNamed(context, DashaRouter.story,
        arguments: StoryDetailArgs(story: story));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return TabScaffold(
      title: app.strings.explore,
      body: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_section != null) _sectionHeader(app),
          if (_section == null) ...[
            _developingSliver(app),
          ],
          _gridSliver(app),
        ],
      ),
    );
  }

  Widget _sectionHeader(AppState app) {
    final section = app.sections
            .any((s) => s.slug == _section)
        ? app.sections.firstWhere((s) => s.slug == _section)
        : _fallbackSections.firstWhere(
            (s) => s.slug == _section,
            orElse: () => _fallbackSections.first,
          );
    return SliverAppBar(
      pinned: true,
      automaticallyImplyLeading: false,
      title: Text(section.label(app.locale)),
      actions: [
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _closeSection,
        ),
      ],
    );
  }

  Widget _developingSliver(AppState app) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            Icon(Icons.autorenew_rounded,
                size: 18, color: SemanticColour.developing.inkOf(context)),
            const SizedBox(width: 8),
            Text(app.strings.developing,
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }

  Widget _gridSliver(AppState app) {
    final sections = app.sections.isEmpty ? _fallbackSections : app.sections;
    if (_section != null) {
      return _sectionResultsSliver(app);
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.6,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final section = sections[index];
            return _sectionTile(app, section);
          },
          childCount: sections.length,
        ),
      ),
    );
  }

  Widget _sectionTile(AppState app, NewsSection section) {
    final theme = Theme.of(context);
    final label = section.label(app.locale);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openSection(section.slug),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                      height: hasTeluguScript(label) ? 1.35 : 1.2,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.arrow_outward_rounded,
                      size: 14, color: theme.colorScheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionResultsSliver(AppState app) {
    return AnimatedBuilder(
      animation: _sectionList,
      builder: (context, _) {
        if (_sectionList.isLoading && _sectionList.items.isEmpty) {
          return const SliverLoading();
        }
        if (_sectionList.isHardEmpty) {
          return SliverError(
            message: _sectionList.error?.message ?? app.strings.errorGeneric,
            onRetry: () => _sectionList.refresh(),
          );
        }
        if (_sectionList.isEmpty) {
          return SliverEmpty(
            title: app.strings.feedEmpty,
            hint: app.strings.feedEmptyHint,
            actionLabel: app.strings.retry,
            onAction: () => _sectionList.refresh(),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
          sliver: SliverList.separated(
            itemCount: _sectionList.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final story = _sectionList.items[index];
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
}
