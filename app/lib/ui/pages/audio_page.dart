import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/error_message.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/audio_controller.dart';
import '../../state/feed_repository.dart';
import '../../state/history_recorder.dart';
import '../../state/paged_list.dart';
import '../main_shell.dart';
import '../router.dart';
import '../../widgets/states_view.dart';

/// The audio edition.
///
/// Stories the newsroom has narrated appear here, and the transport persists
/// across tabs so a reader can keep listening while browsing.
class AudioPage extends StatefulWidget {
  const AudioPage({super.key});

  @override
  State<AudioPage> createState() => _AudioPageState();
}

class _AudioPageState extends TabPageState<AudioPage> {
  final ScrollController _controller = ScrollController();
  late final PagedList _list;
  String? _lastLocale;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _lastLocale = app.locale;
    final repository = FeedRepository(app, CacheNames.audio);
    _list = PagedList((page) => repository.fetch(
          load: () => app.api.feed(language: app.locale, page: page),
        ));
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await _list.refresh();
    if (!mounted) return;
    final audio = context.read<AudioController>();
    // Resume whatever was playing, if it is still in this edition.
    final speakable = _list.items.where(audio.canSpeak).toList();
    if (audio.nowPlaying == null && speakable.isNotEmpty) {
      await audio.play(speakable.first);
    }
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
      title: app.strings.audio,
      body: Column(
        children: [
          const _NowPlaying(),
          Expanded(child: _body(context, app.strings)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, AppStrings strings) {
    return AnimatedBuilder(
      animation: _list,
      builder: (context, _) {
        final narrated = _list.items
            .where(context.watch<AudioController>().canSpeak)
            .toList();
        if (_list.isLoading && _list.items.isEmpty) {
          return const LoadingView();
        }
        if (_list.isHardEmpty) {
          return ErrorState(
            message: errorMessage(strings, _list.error),
            onRetry: _load,
          );
        }
        if (narrated.isEmpty) {
          return EmptyState(
            title: strings.feedEmpty,
            hint: strings.feedEmptyHint,
            icon: Icons.volume_off_outlined,
            actionLabel: strings.retry,
            onAction: _load,
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            controller: _controller,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 110),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: narrated.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final story = narrated[index];
              return _AudioRow(
                story: story,
                onTap: () => _openStory(story),
              );
            },
          ),
        );
      },
    );
  }
}

/// The persistent transport at the top of the audio tab.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final story = audio.nowPlaying;

    if (story == null) {
      return const SizedBox.shrink();
    }

    final title = story.headline(app.locale);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            _artwork(context, story),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                          height: hasTeluguScript(title) ? 1.35 : 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  _scrubBar(audio, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artwork(BuildContext context, Story story) {
    final image = story.imageFor(context.read<AppState>().baseUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: image != null
          ? CachedNetworkImage(
              imageUrl: image,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            )
          : Container(
              width: 52,
              height: 52,
              color: SemanticColour.breaking.badge,
              child: const Icon(Icons.graphic_eq_rounded,
                  color: Colors.white, size: 26),
            ),
    );
  }

  Widget _scrubBar(AudioController audio, ThemeData theme) {
    final total = audio.duration.inMilliseconds;
    final done = audio.position.inMilliseconds;
    final fraction = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 3,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              _mmss(audio.position),
              style: theme.textTheme.labelSmall,
            ),
            const Spacer(),
            // A failure gets its own line below rather than this row, so the
            // whole sentence is read instead of the first few words of it.
            Text(
              audio.isLoading ? '…' : _mmss(audio.duration),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        if (audio.error != null) ...[
          const SizedBox(height: 6),
          Text(
            audio.error!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  String _mmss(Duration d) {
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

/// One narrated story, with play/pause inline.
class _AudioRow extends StatelessWidget {
  const _AudioRow({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final audio = context.watch<AudioController>();
    final app = context.watch<AppState>();
    final theme = Theme.of(context);
    final isCurrent = audio.nowPlaying?.id == story.id;
    final title = story.headline(app.locale);

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(isCurrent && audio.isPlaying
                    ? Icons.pause_circle_filled_rounded
                    : Icons.play_circle_fill_rounded),
                iconSize: 40,
                color: isCurrent
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                onPressed: () {
                  if (isCurrent) {
                    audio.isPlaying ? audio.pause() : audio.resume();
                  } else {
                    audio.play(story);
                  }
                },
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                            height: hasTeluguScript(title) ? 1.35 : 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${story.sectionLabel(app.locale)} · '
                      '${relativeTime(story.publishedAt, strings: app.strings)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
