import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_strings.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/story.dart';
import '../state/app_state.dart';
import '../state/audio_controller.dart';

/// One story filling one screen, in the short-news reader's paradigm.
///
/// The page is the story. There is no list to scan and no card to open: the
/// reader thumbs the screen up and the next story arrives whole, headline and
/// photograph and the outlets behind it. That is the whole interaction, and
/// anything beyond it — a thumbnail, a second meta row, a summary that runs
/// to a paragraph — is what makes a short-news app into a paper.
///
/// What the screen carries is deliberately small: where it happened, when, the
/// headline, and a summary the desk can file in sixty words. The desk's own
/// machinery stays off the reader's screen; a reader who wants the reasoning
/// behind a story goes to the desk's tool, and a reader who wants the story
/// stays here.
class SwipeStoryView extends StatelessWidget {
  const SwipeStoryView({
    super.key,
    required this.story,
    required this.regionLabel,
    required this.onTap,
    this.heroTag,
  });

  final Story story;

  /// The question this story answers — ఇప్పుడు, మీ చుట్టూ, తెలంగాణ. A reader
  /// swiping through a stream needs to know where in it they have landed, and
  /// the region is that bearings, drawn small so it does not outrank the
  /// headline beneath it.
  final String regionLabel;

  final VoidCallback onTap;

  /// The hero tag the photograph shares with the story page, so the picture
  /// the reader is looking at is the picture that arrives. Only one screen at
  /// a time carries a tag, which the pager guarantees.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final image = story.imageFor(app.baseUrl);
    return GestureDetector(
      onTap: _tap(onTap),
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _photograph(context, image),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bearings(context, strings),
                    const SizedBox(height: 7),
                    _headline(context, strings),
                    const SizedBox(height: 8),
                    _summary(context),
                    const Spacer(),
                    _attribution(context, strings),
                  ],
                ),
              ),
            ),
            _actions(context, app, strings),
          ],
        ),
      ),
    );
  }

  /// The photograph occupies the top of the screen and nothing else, the way a
  /// news magazine lays a page: the picture earns its share of the screen and
  /// the type sits under it rather than beside it.
  ///
  /// A story without a photograph does not get a placeholder. An empty box
  /// where a picture was expected is the loudest thing on a page that has
  /// nothing to say, so the space goes to the type instead.
  Widget _photograph(BuildContext context, String? image) {
    if (image == null || image.isEmpty) return const SizedBox(height: 4);
    final height = MediaQuery.of(context).size.height * 0.42;
    final picture = ClipRect(
      child: CachedNetworkImage(
        imageUrl: image,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          height: height,
          width: double.infinity,
        ),
        errorWidget: (context, url, error) => const SizedBox(height: 4),
      ),
    );
    return Stack(
      children: [
        if (heroTag == null) picture else Hero(tag: heroTag!, child: picture),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bearings(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    // The badge and the gap it earns come from the same branch, so a story
    // that is neither breaking nor developing draws neither.
    final children = <Widget>[];
    if (story.isBreaking) {
      children.add(_Tag(
        label: strings.breaking,
        colour: SemanticColour.breaking,
      ));
      children.add(const SizedBox(width: 7));
    } else if (story.isDeveloping) {
      children.add(_Tag(
        label: strings.developing,
        colour: SemanticColour.developing,
      ));
      children.add(const SizedBox(width: 7));
    }
    children.add(
      Text(
        regionLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
    children.add(const _Dot());
    children.add(
      Text(
        story.sectionLabel(context.read<AppState>().locale),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  Widget _headline(BuildContext context, AppStrings strings) {
    final text = story.headline(context.read<AppState>().locale);
    return Text(
      text,
      style: storyHeadline(context, text, size: 21, maxLines: 4),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// The desk's sixty words, and not a syllable more of them. The line clamp
  /// is the design constraint and the guarantee: a story that cannot be said
  /// in this much room is a story the stream is not the right home for.
  Widget _summary(BuildContext context) {
    final text = story.lead;
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: teluguBody(context, text, size: 14.5)
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// Where and when. The place is the answer the stream exists to give, and
  /// the time is relative, because "two hours ago" is what a reader can act
  /// on.
  Widget _attribution(BuildContext context, AppStrings strings) {
    final theme = Theme.of(context);
    final place = story.mandal ?? story.district;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(Icons.place_rounded,
              size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          if (place != null && place.isNotEmpty)
            Flexible(
              child: Text(
                place,
                style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Text(
              strings.stateEdition,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          const _Dot(),
          Text(
            relativeTime(story.publishedAt, strings: strings),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          if (story.isDeveloping) ...[
            Icon(Icons.trending_up_rounded,
                size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              strings.developing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, AppState app, AppStrings strings) {
    final saved = app.isBookmarked(story.id);
    final audio = context.watch<AudioController>();
    final playing = audio.nowPlaying?.id == story.id && audio.isPlaying;
    return SafeArea(
      top: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor, width: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            children: [
              if (audio.canSpeak(story))
                _ActionButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.headphones_rounded,
                  label: strings.listen,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (playing) {
                      audio.pause();
                    } else {
                      audio.play(story);
                    }
                  },
                ),
              const Spacer(),
              _ActionButton(
                icon: saved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: strings.save,
                highlighted: saved,
                onTap: () {
                  HapticFeedback.selectionClick();
                  app.toggleBookmark(story.id);
                },
              ),
              const SizedBox(width: 4),
              _ActionButton(
                icon: Icons.share_rounded,
                label: strings.shareStory,
                onTap: () {
                  HapticFeedback.selectionClick();
                  audio.pause();
                  _share(context, app, strings);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(
      BuildContext context, AppState app, AppStrings strings) async {
    // The name comes from the string table rather than being set in stone in
    // Telugu here: an English reader sharing a story should share an English
    // sign-off, not a mixed-script one.
    final headline = story.headline(app.locale);
    final text = '$headline\n${story.lead}\n\n'
        '${strings.sharedFrom} ${strings.appName}';
    await Share.share(text, subject: headline);
  }
}

/// A tap on a story is the app's most-used gesture, so it carries a physical
/// response: the reader feels the story land before the page starts to move.
VoidCallback _tap(VoidCallback onTap) {
  return () {
    HapticFeedback.lightImpact();
    onTap();
  };
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '·',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The breaking/developing badge, drawn small and flat so it does not
/// outweigh the headline it sits above.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.colour});

  final String label;
  final SemanticColour colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colour.badge,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              fontSize: 9.5,
              height: 1.3,
            ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: highlighted
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: highlighted
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: highlighted
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
