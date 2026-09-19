import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/theme.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// The breaking rail.
///
/// Breaking stories are presented in full-bleed reverse chronological order,
/// with the newest at the top and nothing else competing for attention.
class BreakingPage extends StatefulWidget {
  const BreakingPage({super.key});

  @override
  State<BreakingPage> createState() => _BreakingPageState();
}

class _BreakingPageState extends TabPageState<BreakingPage> {
  final ScrollController _controller = ScrollController();
  late final PagedList _list;
  String? _lastLocale;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    final repository = FeedRepository(app, CacheNames.breaking);
    _lastLocale = app.locale;
    _list = PagedList((page) => repository.fetch(
          load: () => app.api.breaking(page: page),
        ));
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _list.refresh());
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
    if (_lastLocale != app.locale) {
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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return TabScaffold(
      title: app.strings.breaking,
      body: _body(context, app.strings),
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
            icon: Icons.bolt_outlined,
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
                return _list.isLoadingMore && _list.hasMore
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : const SizedBox.shrink();
              }
              final story = _list.items[index];
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                        color: SemanticColour.breaking.inkOf(context)
                            .withValues(alpha: 0.7),
                        width: 3),
                  ),
                ),
                child: StoryCard(
                  story: story,
                  onTap: () => _openStory(story),
                  compact: index > 0,
                ),
              );
            },
          ),
        );
      },
    );
  }
}
