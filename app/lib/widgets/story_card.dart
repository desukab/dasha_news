import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/story.dart';
import '../state/app_state.dart';

/// One story in a list, drawn at the density its position on the page demands.
///
/// A front page is not a uniform grid of equal cards: it is a lead, a few
/// stories with summaries, and a run of briefs. Three densities are enough to
/// express that, and the page picks one per slot.
///
/// What the card does *not* draw is deliberate. Evidence levels, confidence
/// scores, source counts and conflict flags are the desk's machinery; they
/// belong to the editor's tool, not to a reader scanning a page. The reader
/// gets the headline, the summary, where it happened, when, and the outlets
/// behind it on the story page.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    this.onTap,
    this.showImage = true,
    this.compact = false,
    this.variant,
    this.trailing,
    this.heroTag,
  });

  final Story story;
  final VoidCallback? onTap;

  /// Kept for the callers that have not been moved to [variant] yet.
  final bool showImage;

  /// Kept for the same callers: `compact: true` is [StoryVariant.brief].
  final bool compact;

  /// How the card is drawn. When null it is derived from [compact], so an
  /// unconverted call site renders as it did before.
  final StoryVariant? variant;

  final Widget? trailing;

  /// The hero tag for the photograph, so it flies into the story page. Pass it
  /// only from a list where this story appears exactly once.
  final String? heroTag;

  StoryVariant get _variant =>
      variant ?? (compact ? StoryVariant.brief : StoryVariant.standard);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final language = app.locale;
    final headline = story.headline(language);
    switch (_variant) {
      case StoryVariant.lead:
        return _LeadCard(
          story: story,
          headline: headline,
          strings: strings,
          onTap: onTap,
          heroTag: heroTag,
        );
      case StoryVariant.brief:
        return _BriefCard(
          story: story,
          headline: headline,
          strings: strings,
          onTap: onTap,
        );
      case StoryVariant.standard:
        return _StandardCard(
          story: story,
          headline: headline,
          strings: strings,
          showImage: showImage,
          trailing: trailing,
          onTap: onTap,
        );
    }
  }
}

/// How a story is drawn, which is a function of where it sits on the page.
enum StoryVariant {
  /// The lead: full width, photograph above the type, summary paragraph.
  lead,

  /// A standard story: headline, a short summary, and a meta row, with a small
  /// thumbnail when the desk has a photograph. Most of the page is these.
  standard,

  /// A brief: headline and meta only, separated by a rule.
  brief,
}

// -- shared pieces -----------------------------------------------------------

class _CardShell extends StatelessWidget {
  const _CardShell({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: _tap(onTap),
        customBorder: Theme.of(context).cardTheme.shape,
        child: child,
      ),
    );
  }
}

/// A tap on a story is the app's most-used gesture, so it gets a physical
/// one: the reader feels the story land before the page starts to move.
VoidCallback? _tap(VoidCallback? onTap) {
  if (onTap == null) return null;
  return () {
    HapticFeedback.lightImpact();
    onTap();
  };
}

/// The breaking/developing badge, drawn small and flat so it does not
/// outweigh the headline next to it.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

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

/// Where and when, the way a folio line reads. Shown on one line because a
/// story card has to earn its height, and two meta rows is what makes a feed
/// feel like a form.
class _Folio extends StatelessWidget {
  const _Folio({required this.story, required this.strings, this.brief = false});

  final Story story;
  final AppStrings strings;
  final bool brief;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = story.sectionLabel(context.read<AppState>().locale);
    final time = relativeTime(story.publishedAt, strings: strings);
    // A state alone ("Telangana") is not a location a reader learns anything
    // from on a Telangana front page; only a district or a mandal is.
    final place = story.mandal ?? story.district;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.8,
              color: brief ? theme.colorScheme.primary : muted,
              fontWeight: FontWeight.w800,
              fontSize: 9.5,
            ),
          ),
          if (place != null && place.isNotEmpty) ...[
            TextSpan(
              text: ' · $place',
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
          if (time.isNotEmpty) ...[
            TextSpan(
              text: ' · $time',
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.url,
    required this.width,
    required this.height,
    this.radius = 4,
    this.heroTag,
  });

  final String url;
  final double width;
  final double height;
  final double radius;

  /// When set, the photograph carries a hero tag so it flies into the story
  /// page. Only one card per screen may carry a given tag, so callers pass it
  /// only where a story appears once.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          width: width,
          height: height,
        ),
        errorWidget: (context, url, error) => const SizedBox.shrink(),
      ),
    );
    if (heroTag == null) return image;
    return Hero(tag: heroTag!, child: image);
  }
}

// -- the variants ------------------------------------------------------------

/// The lead story: photograph, then the headline, then one summary line. This
/// is the story the page is sold on, so it is the one slot allowed a picture
/// and a summary — and it is still one card, not a poster.
class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.story,
    required this.headline,
    required this.strings,
    this.onTap,
    this.heroTag,
  });

  final Story story;
  final String headline;
  final AppStrings strings;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final image = story.imageFor(context.read<AppState>().baseUrl);
    final hasPhoto = image != null && image.isNotEmpty;
    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto) ...[
              _Photo(
                url: image,
                width: double.infinity,
                height: 148,
                radius: 6,
                heroTag: heroTag,
              ),
              const SizedBox(height: 9),
            ],
            if (story.isBreaking || story.isDeveloping) ...[
              _badgeRow(context),
              const SizedBox(height: 6),
            ],
            Text(
              headline,
              style: storyHeadline(context, headline, size: 18, maxLines: 3),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            _Folio(story: story, strings: strings),
            if (story.lead.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                story.lead,
                style: teluguBody(context, story.lead, size: 13.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badgeRow(BuildContext context) {
    return Row(
      children: [
        if (story.isBreaking)
          _Badge(label: strings.breaking, colour: SemanticColour.breaking)
        else if (story.isDeveloping)
          _Badge(label: strings.developing, colour: SemanticColour.developing),
      ],
    );
  }
}

/// A standard story: headline, a two-line summary, and the meta row, with a
/// small thumbnail beside the type when the desk has a photograph. The bulk
/// of a page is these, which is what makes a page of twelve stories readable.
class _StandardCard extends StatelessWidget {
  const _StandardCard({
    required this.story,
    required this.headline,
    required this.strings,
    required this.showImage,
    this.trailing,
    this.onTap,
  });

  final Story story;
  final String headline;
  final AppStrings strings;
  final bool showImage;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final image = story.imageFor(context.read<AppState>().baseUrl);
    final hasPhoto = showImage && image != null && image.isNotEmpty;
    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 10, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (story.isBreaking || story.isDeveloping) ...[
                    _badgeRow(context),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    headline,
                    style: storyHeadline(context, headline, size: 15,
                            maxLines: 3)
                        .copyWith(fontWeight: FontWeight.w700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  _Folio(story: story, strings: strings),
                  if (story.lead.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      story.lead,
                      style: teluguBody(context, story.lead, size: 13),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (hasPhoto) ...[
              const SizedBox(width: 10),
              _Photo(url: image, width: 72, height: 72, radius: 6),
            ],
          ],
        ),
      ),
    );
  }

  Widget _badgeRow(BuildContext context) {
    return Row(
      children: [
        if (story.isBreaking)
          _Badge(label: strings.breaking, colour: SemanticColour.breaking)
        else if (story.isDeveloping)
          _Badge(label: strings.developing, colour: SemanticColour.developing),
      ],
    );
  }
}

/// A brief: type only, no card and no photograph. The page's density comes
/// from here — a rule under the story instead of a gap between cards.
class _BriefCard extends StatelessWidget {
  const _BriefCard({
    required this.story,
    required this.headline,
    required this.strings,
    this.onTap,
  });

  final Story story;
  final String headline;
  final AppStrings strings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: _tap(onTap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Folio(story: story, strings: strings, brief: true),
                const SizedBox(height: 4),
                Text(
                  headline,
                  style: storyHeadline(context, headline, size: 14.5,
                          maxLines: 3)
                      .copyWith(fontWeight: FontWeight.w700),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.6,
            color: theme.dividerColor,
          ),
        ],
      ),
    );
  }
}
