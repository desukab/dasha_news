import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/error_message.dart';
import '../../core/format.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../../widgets/story_card.dart';

/// Free-text search across published stories.
///
/// The query is the reader's own words; results are ranked by the newsroom,
/// which is where the similarity logic belongs. The app holds the last query
/// so a rotation or a tab switch does not lose what was typed.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _controller = ScrollController();
  late final PagedList _list;
  bool _hasSearched = false;
  String? _lastLocale;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _lastLocale = app.locale;
    final repository = FeedRepository(app, CacheNames.search);
    _list = PagedList((page) => repository.fetch(
          load: () => app.api.search(
            query: _query.text.trim(),
            language: app.locale,
          ),
        ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (_lastLocale != app.locale && _hasSearched) {
      _lastLocale = app.locale;
      _submit();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _controller.dispose();
    _list.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _query.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _hasSearched = true);
    _list.refresh();
  }

  void _clear() {
    _query.clear();
    setState(() => _hasSearched = false);
    _focus.requestFocus();
  }

  void _openStory(Story story) {
    context.read<HistoryRecorder>().start(story.id);
    Navigator.pushNamed(context, DashaRouter.story,
        arguments: StoryDetailArgs(story: story));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(app.strings.search,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: const [LanguageButton()],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: _searchField(app.strings),
        ),
      ),
      body: _hasSearched ? _results(context, app.strings) : _suggestions(app),
    );
  }

  Widget _searchField(AppStrings strings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _query,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _submit(),
        style: TextStyle(
          height: hasTeluguScript(_query.text) ? 1.4 : 1.3,
        ),
        decoration: InputDecoration(
          hintText: strings.searchHint,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _clear,
                )
              : null,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _suggestions(AppState app) {
    final sections = app.sections;
    if (sections.isEmpty) {
      return Center(
        child: Text(
          app.strings.searchHint,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(app.strings.explore,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final section in sections.take(14))
              ActionChip(
                label: Text(section.label(app.locale)),
                onPressed: () {
                  _query.text = section.label(app.locale);
                  _submit();
                },
              ),
          ],
        ),
      ],
    );
  }

  Widget _results(BuildContext context, AppStrings strings) {
    return AnimatedBuilder(
      animation: _list,
      builder: (context, _) {
        if (_list.isLoading && _list.items.isEmpty) {
          return const LoadingView();
        }
        if (_list.isHardEmpty) {
          return ErrorState(
            message: errorMessage(strings, _list.error),
            onRetry: () => _list.refresh(),
          );
        }
        if (_list.isEmpty) {
          return EmptyState(
            title: strings.searchEmpty,
            hint: '"${_query.text.trim()}"',
            icon: Icons.search_off_rounded,
            actionLabel: strings.retry,
            onAction: () => _list.refresh(),
          );
        }
        return ListView.separated(
          controller: _controller,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
          itemCount: _list.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final story = _list.items[index];
            return StoryCard(
              story: story,
              onTap: () => _openStory(story),
              compact: index > 0,
            );
          },
        );
      },
    );
  }
}
