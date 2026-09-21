import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api_client.dart';
import '../../core/app_strings.dart';
import '../../core/error_message.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/audio_controller.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../main_shell.dart';
import '../widgets/masthead.dart';

/// The full story: headline, body, where and when it happened.
///
/// The page shows a reader what a newspaper shows a reader. The desk's own
/// machinery — which claim rests on which evidence level, how confident the
/// pipeline is, which outlets corroborate which — is not a reader's concern;
/// it lives in the editor's tool. What the reader gets is the story itself.
class StoryDetailPage extends StatefulWidget {
  const StoryDetailPage({super.key, required this.args});

  final StoryDetailArgs args;

  @override
  State<StoryDetailPage> createState() => _StoryDetailPageState();
}

class _StoryDetailPageState extends State<StoryDetailPage> {
  late Story _story;
  bool _loading = true;
  String? _error;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _story = widget.args.story ??
        Story(
          id: widget.args.id ?? 0,
          clusterId: '',
          slug: widget.args.slug ?? '',
          section: 'telangana',
          status: 'published',
          importance: 0,
          isBreaking: false,
          isDeveloping: false,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    try {
      final detail = widget.args.slug != null && widget.args.id == null
          ? await app.api.storyBySlug(widget.args.slug!)
          : await app.api.story(widget.args.resolvedId);
      if (!mounted) return;
      setState(() {
        _story = detail;
        _loading = false;
      });
    } on ApiException catch (exc) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(app.strings, exc);
        _offline = exc.isOffline;
        _loading = false;
      });
    }
  }

  void _toggleBookmark() {
    final app = context.read<AppState>();
    app.toggleBookmark(_story.id);
  }

  void _share() {
    // Sharing is delegated to the system sheet; we never post on the reader's
    // behalf, and the link points at the Dasha story, not the source article.
    final uri = Uri.parse('${appBaseUrl()}/s/${_story.slug}');
    Share.share(uri.toString(), subject: _story.headline(appLocaleCode()));
  }

  String appBaseUrl() => context.read<AppState>().baseUrl;
  String appLocaleCode() => context.read<AppState>().locale;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final audio = context.watch<AudioController>();
    final strings = app.strings;
    return Scaffold(
      // A load that failed leaves _loading false, so gating the error state
      // on _loading would render the empty stub story instead of telling the
      // reader what happened.
      body: _error != null
          ? ErrorState(
              // _error is already the localised sentence, set in _load.
              message: _error!,
              onRetry: _load,
              offlineHint: _offline,
            )
          : CustomScrollView(
              slivers: [
                _appBar(context, app, audio, strings),
                if (_loading && _story.bodyTe == null)
                  const SliverLoading()
                else ...[
                  _headline(context, app, strings),
                  _byline(context, app, strings),
                  if (_story.imageUrl != null) _heroImage(context, app),
                  if (audio.canSpeak(_story))
                    _listenBar(context, audio, strings),
                  _body(context, app, strings),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ],
            ),
      bottomNavigationBar: _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        context: context,
                        icon: app.isBookmarked(_story.id)
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        label: app.isBookmarked(_story.id)
                            ? strings.savedStory
                            : strings.saveStory,
                        highlighted: app.isBookmarked(_story.id),
                        onPressed: _toggleBookmark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionButton(
                        context: context,
                        icon: Icons.share_rounded,
                        label: strings.shareStory,
                        onPressed: _share,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _appBar(BuildContext context, AppState app, AudioController audio,
      AppStrings strings) {
    // The paper's mark, not a translated word: the shell shows the same one
    // above every tab, so a story page reads as the same publication.
    return const SliverAppBar(
      floating: true,
      pinned: false,
      snap: true,
      title: DashaMonogram(extent: 30),
      actions: [LanguageButton()],
    );
  }

  Widget _headline(BuildContext context, AppState app, AppStrings strings) {
    final text = _story.headline(app.locale);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_story.isBreaking)
                  _kicker(context, strings.breaking,
                      SemanticColour.breaking.inkOf(context))
                else if (_story.isDeveloping)
                  _kicker(context, strings.developing,
                      SemanticColour.developing.inkOf(context))
                else
                  _kicker(context, _story.sectionLabel(app.locale),
                      Theme.of(context).colorScheme.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    height: hasTeluguScript(text) ? 1.36 : 1.22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    fontSize: 20,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kicker(BuildContext context, String label, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              fontSize: 10.5,
            ),
      ),
    );
  }

  Widget _byline(BuildContext context, AppState app, AppStrings strings) {
    final place = _story.place;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            if (place != null) _meta(context, Icons.place_outlined, place),
            _meta(
                context,
                Icons.schedule_rounded,
                '${absoluteTime(_story.publishedAt)} · '
                    '${relativeTime(_story.publishedAt, strings: strings)}'),
            _meta(
                context,
                Icons.menu_book_rounded,
                strings.readingTime(
                    readingTime(_story.body(app.locale)))),
          ],
        ),
      ),
    );
  }

  Widget _meta(BuildContext context, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _heroImage(BuildContext context, AppState app) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: Hero(
          tag: 'story-photo-${_story.id}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: _story.imageFor(app.baseUrl)!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (context, url, error) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _listenBar(BuildContext context, AudioController audio,
      AppStrings strings) {
    final isCurrent = audio.nowPlaying?.id == _story.id;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.headphones_rounded,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isCurrent && audio.isPlaying
                      ? strings.pause
                      : strings.listen,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (isCurrent) {
                    audio.isPlaying ? audio.pause() : audio.resume();
                  } else {
                    audio.play(_story);
                  }
                },
                icon: Icon(isCurrent && audio.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded),
                label: Text(
                  isCurrent && audio.isPlaying ? strings.pause : strings.listen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppState app, AppStrings strings) {
    final text = _story.body(app.locale);
    if (text.trim().isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(strings.holdNote,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ),
      );
    }
    final paragraphs = text
        .split(RegExp(r'\n+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < paragraphs.length; i++) ...[
              Text(
                paragraphs[i],
                textAlign: TextAlign.justify,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: hasTeluguScript(text) ? 1.68 : 1.58,
                      fontSize: 15.5,
                    ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              strings.originalVsSummary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: highlighted
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHigh,
        foregroundColor: highlighted
            ? theme.colorScheme.onPrimary
            : theme.colorScheme.onSurface,
        minimumSize: const Size.fromHeight(42),
        textStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}
