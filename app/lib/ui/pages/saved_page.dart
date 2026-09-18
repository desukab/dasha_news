import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_strings.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/history_recorder.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// The reader's saved stories.
///
/// Bookmarks are held locally as well as on the server, so this screen still
/// works offline and the save badge appears the instant the reader taps it.
class SavedPage extends StatefulWidget {
  const SavedPage({super.key});

  @override
  State<SavedPage> createState() => _SavedPageState();
}

class _SavedPageState extends TabPageState<SavedPage> {
  final ScrollController _controller = ScrollController();
  List<Story> _items = [];
  bool _loading = true;
  bool _offline = false;
  String? _lastLocale;

  @override
  void initState() {
    super.initState();
    _lastLocale = context.read<AppState>().locale;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _offline = false;
    });
    try {
      final items = await app.api.bookmarks(deviceId: app.storage.deviceId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() {
        _offline = exc.isOffline;
        _loading = false;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_lastLocale != app.locale) {
      _lastLocale = app.locale;
      _load();
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
  void dispose() {
    _controller.dispose();
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
      title: app.strings.saved,
      body: _body(context, app.strings),
    );
  }

  Widget _body(BuildContext context, AppStrings strings) {
    if (_loading) {
      return const LoadingView();
    }
    if (_items.isEmpty) {
      return EmptyState(
        title: strings.bookmarksEmpty,
        hint: _offline ? strings.offlineHint : strings.bookmarksEmptyHint,
        icon: Icons.bookmark_border_outlined,
        actionLabel: _offline ? null : strings.retry,
        onAction: _offline ? null : _load,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 110),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final story = _items[index];
          return Dismissible(
            key: ValueKey('bookmark-${story.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
            onDismissed: (_) async {
              await context.read<AppState>().removeBookmark(story.id);
              if (!mounted) return;
              setState(() => _items.removeWhere((s) => s.id == story.id));
            },
            child: StoryCard(
              story: story,
              onTap: () => _openStory(story),
              compact: index > 0,
            ),
          );
        },
      ),
    );
  }
}
