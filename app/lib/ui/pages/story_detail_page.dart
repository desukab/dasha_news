import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_strings.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/story.dart';
import '../../state/app_state.dart';
import '../../state/audio_controller.dart';
import '../router.dart';
import '../../widgets/states_view.dart';
import '../main_shell.dart';

/// The full story: headline, body, every fact with its evidence level, every
/// source that reported it, and every correction since publication.
///
/// This page is the product's promise. Nothing here is hidden: the reader can
/// see exactly which claim rests on which evidence and which outlet said it.
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
          evidenceScore: 0,
          numSources: 0,
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
        _error = exc.message;
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
      body: _error != null && _loading
          ? ErrorState(
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
                  if (_story.imageUrl != null) _heroImage(context),
                  if (_story.hasAudio) _listenBar(context, audio, strings),
                  _body(context, app, strings),
                  if (_story.updates.isNotEmpty)
                    _updates(context, app, strings),
                  _facts(context, app, strings),
                  _sources(context, app, strings),
                  _trustSummary(context, app, strings),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ],
            ),
      floatingActionButton: _error != null
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(
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
                _actionButton(
                  context: context,
                  icon: Icons.share_rounded,
                  label: strings.shareStory,
                  onPressed: _share,
                ),
              ],
            ),
    );
  }

  Widget _appBar(BuildContext context, AppState app, AudioController audio,
      AppStrings strings) {
    return SliverAppBar(
      floating: true,
      pinned: false,
      snap: true,
      title: Text(
        strings.appName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: const [LanguageButton()],
    );
  }

  Widget _headline(BuildContext context, AppState app, AppStrings strings) {
    final text = _story.headline(app.locale);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
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
            const SizedBox(height: 10),
            Text(
              text,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    height: hasTeluguScript(text) ? 1.4 : 1.24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                '${readingTime(_story.body(app.locale))} ${strings.minRead}'),
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

  Widget _heroImage(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: CachedNetworkImage(
              imageUrl: _story.imageUrl!,
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
    );
  }

  Widget _listenBar(BuildContext context, AudioController audio,
      AppStrings strings) {
    final isCurrent = audio.nowPlaying?.id == _story.id;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
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
          padding: const EdgeInsets.all(20),
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < paragraphs.length; i++) ...[
              Text(
                paragraphs[i],
                textAlign: TextAlign.justify,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: hasTeluguScript(text) ? 1.72 : 1.62,
                      fontSize: 16.5,
                    ),
              ),
              const SizedBox(height: 14),
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

  Widget _updates(BuildContext context, AppState app, AppStrings strings) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _subhead(context, strings.updates, Icons.history_rounded),
            const SizedBox(height: 8),
            for (final update in _story.updates) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: update.isCorrection
                      ? SemanticColour.disputed.inkOf(context)
                          .withValues(alpha: 0.07)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: update.isCorrection
                      ? Border.all(
                          color: SemanticColour.disputed.inkOf(context)
                              .withValues(alpha: 0.3))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          update.isCorrection
                              ? Icons.edit_note_rounded
                              : Icons.update_rounded,
                          size: 16,
                          color: update.isCorrection
                              ? SemanticColour.disputed.inkOf(context)
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          update.isCorrection
                              ? strings.corrections
                              : strings.updates,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: update.isCorrection
                                        ? SemanticColour.disputed.inkOf(
                                            context)
                                        : Theme.of(context)
                                            .colorScheme
                                            .primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const Spacer(),
                        Text(
                          relativeTime(update.createdAt, strings: app.strings),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                    if (update.headline != null) ...[
                      const SizedBox(height: 6),
                      Text(update.headline!,
                          style: Theme.of(context).textTheme.titleSmall),
                    ],
                    if (update.text(app.locale).isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        update.text(app.locale),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              height: hasTeluguScript(update.text(app.locale))
                                  ? 1.6
                                  : 1.5,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _facts(BuildContext context, AppState app, AppStrings strings) {
    final facts = [..._story.facts]..sort((a, b) => a.rank.compareTo(b.rank));
    if (facts.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _subhead(context, strings.facts, Icons.fact_check_outlined),
            const SizedBox(height: 10),
            for (final fact in facts) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color:
                          evidenceColour(fact.evidenceLevel).inkOf(context),
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _evidenceTag(context, fact),
                        const Spacer(),
                        Text(
                          '${(fact.confidence * 100).round()}%',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fact.text(app.locale),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height:
                                hasTeluguScript(fact.text(app.locale)) ? 1.6 : 1.5,
                          ),
                    ),
                    if (fact.attributedTo != null &&
                        fact.attributedTo!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${strings.attributedTo}: ${fact.attributedTo}',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _evidenceTag(BuildContext context, Fact fact) {
    final colour = evidenceColour(fact.evidenceLevel).inkOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        fact.label(context.read<AppState>().locale).toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colour,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 10,
            ),
      ),
    );
  }

  Widget _sources(BuildContext context, AppState app, AppStrings strings) {
    if (_story.sources.isEmpty) return const SliverToBoxAdapter(child: SizedBox());
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _subhead(context, strings.sources, Icons.link_rounded),
            const SizedBox(height: 8),
            for (final source in _story.sources) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.sourceName ?? source.displayUrl,
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            source.articleTitle ??
                                source.articleUrl ??
                                source.siteUrl ??
                                '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                source.corroborates
                                    ? Icons.verified_rounded
                                    : (source.conflictsWith ?? '').isNotEmpty
                                        ? Icons.warning_amber_rounded
                                        : Icons.info_outline_rounded,
                                size: 13,
                                color: source.corroborates
                                    ? SemanticColour.fact.inkOf(context)
                                    : (source.conflictsWith ?? '')
                                            .isNotEmpty
                                        ? SemanticColour.disputed.inkOf(
                                            context)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  source.corroborates
                                      ? strings.corroborated
                                      : (source.conflictsWith ?? '').isNotEmpty
                                          ? strings.inConflict
                                          : strings.sources,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: source.corroborates
                                            ? SemanticColour.fact.inkOf(
                                                context)
                                            : (source.conflictsWith ?? '')
                                                    .isNotEmpty
                                                ? SemanticColour.disputed
                                                    .inkOf(context)
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              if (source.publishedAt != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  relativeTime(source.publishedAt,
                                      strings: app.strings),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall,
                                ),
                              ],
                            ],
                          ),
                          if ((source.conflictsWith ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              source.conflictsWith!,
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: SemanticColour.disputed
                                            .inkOf(context),
                                        fontStyle: FontStyle.italic,
                                      ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (source.articleUrl != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        tooltip: strings.readAtSource,
                        onPressed: () async {
                          final uri = Uri.parse(source.articleUrl!);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trustSummary(BuildContext context, AppState app, AppStrings strings) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _subhead(context, strings.evidence, Icons.shield_outlined),
              const SizedBox(height: 10),
              _meter(
                context,
                label: strings.evidence,
                value: _story.evidenceScore,
                colour: SemanticColour.fact.inkOf(context),
              ),
              const SizedBox(height: 8),
              _meter(
                context,
                label: strings.confidence,
                value: _story.confidence,
                colour: SemanticColour.developing.inkOf(context),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.groups_rounded,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_story.numSources} ${strings.sources} · '
                      '${_story.isCorroborated ? strings.corroborated : strings.sources}',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
              if (_story.isCorrected) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.edit_outlined,
                        size: 16, color: SemanticColour.developing.inkOf(
                            context)),
                    const SizedBox(width: 6),
                    Text(
                      '${strings.corrections}: ${_story.correctionsCount} · '
                          'v${_story.version}',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: SemanticColour.developing.inkOf(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _meter(BuildContext context,
      {required String label, required double value, required Color colour}) {
    final theme = Theme.of(context);
    final clamped = value.clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label,
              style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: colour,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 38,
          child: Text(
            '${(clamped * 100).round()}%',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }

  Widget _subhead(BuildContext context, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
      ],
    );
  }

  Widget _actionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool highlighted = false,
  }) {
    return FloatingActionButton.extended(
      heroTag: 'story-action-$label',
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      backgroundColor: highlighted
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      foregroundColor: highlighted
          ? Theme.of(context).colorScheme.onPrimary
          : Theme.of(context).colorScheme.onSurface,
    );
  }
}
