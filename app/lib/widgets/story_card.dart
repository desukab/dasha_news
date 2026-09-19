import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/story.dart';
import '../state/app_state.dart';

/// One story in a list, drawn the way its position on the page demands.
///
/// A front page is not a uniform grid of cards: the lead story carries the
/// photograph and the summary, and the briefs underneath it are dense type
/// separated by rules. The card keeps the editorial contract either way — what
/// the claim's evidence level is, how many outlets reported it, and whether
/// they agree — and draws only as much of it as the variant has room for.
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

  /// Kept for the same callers: `compact: true` is `StoryVariant.brief`.
  final bool compact;

  /// How the card is drawn. When null it is derived from [compact], so an
  /// unconverted call site renders as it did before.
  final StoryVariant? variant;

  final Widget? trailing;

  /// The hero tag for the photograph, so it flies into the story page. Pass it
  /// only from a list where this story appears exactly once.
  final String? heroTag;

  StoryVariant get _variant => variant ?? (compact ? StoryVariant.brief : StoryVariant.standard);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final language = app.locale;
    final headline = story.headline(language);
    final v = _variant;

    switch (v) {
      case StoryVariant.lead:
        return _LeadCard(
          story: story,
          headline: headline,
          language: language,
          strings: strings,
          onTap: onTap,
          heroTag: heroTag,
        );
      case StoryVariant.secondary:
        return _SecondaryCard(
          story: story,
          headline: headline,
          language: language,
          strings: strings,
          onTap: onTap,
          heroTag: heroTag,
        );
      case StoryVariant.brief:
        return _BriefCard(
          story: story,
          headline: headline,
          language: language,
          strings: strings,
          onTap: onTap,
        );
      case StoryVariant.standard:
        return _StandardCard(
          story: story,
          headline: headline,
          language: language,
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

  /// A secondary story: column-width, square photograph, three-line headline.
  secondary,

  /// A brief: type only, separated by a rule, no card and no photograph.
  brief,

  /// The pre-redesign card, used by screens that have not been laid out as a
  /// front page yet.
  standard,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.badge,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 10,
              height: 1.35,
            ),
      ),
    );
  }
}

/// The strongest of the story's claims, absent a fact list (the feed endpoint
/// omits facts), is not drawn as a guess: the chip is simply left out.
Widget? _evidenceChip(
  BuildContext context,
  Story story,
  AppStrings strings,
  String language,
) {
  final ranked = [...story.facts]..sort((a, b) => a.rank.compareTo(b.rank));
  final strongest = ranked.isEmpty ? null : ranked.first;
  if (strongest == null) return null;
  final level = strongest.evidenceLevel;
  if (level.isEmpty) return null;
  return _chip(
    context,
    icon: Icons.shield_outlined,
    label: strongest.label(language),
    colour: evidenceColour(level),
  );
}

Widget _sourcesChip(
  BuildContext context,
  Story story,
  AppStrings strings,
) {
  return _chip(
    context,
    icon: story.isCorroborated ? Icons.verified_rounded : Icons.info_outline,
    label: '${story.numSources} ${strings.sources}',
    colour:
        story.isCorroborated ? SemanticColour.fact : SemanticColour.claim,
    filled: story.isCorroborated,
  );
}

/// A tonal tag: the ink at full strength for the label and icon, a faint tint
/// of the same ink for the ground.
///
/// The ground is deliberately *not* a solid fill. A solid mid-tone would need
/// white type to stay legible, and white type on a mid-tone is the one
/// combination the palette cannot serve in both brightnesses — so the ink
/// stays the ink and the ground stays out of its way.
Widget _chip(
  BuildContext context, {
  required IconData icon,
  required String label,
  required SemanticColour colour,
  bool filled = false,
}) {
  final theme = Theme.of(context);
  final ink = colour.inkOf(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: filled ? 0.16 : 0.09),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: ink.withValues(alpha: filled ? 0.45 : 0.24)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: ink),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: ink,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
          ),
        ),
      ],
    ),
  );
}

/// Section label and relative time, the way a folio line reads.
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
    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 0.9,
              color: brief ? theme.colorScheme.primary : muted,
              fontWeight: FontWeight.w800,
              fontSize: brief ? 10 : null,
            ),
          ),
          if (time.isNotEmpty) ...[
            TextSpan(
              text: ' · $time',
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
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

/// The lead story: photograph, then the headline at nameplate size, then the
/// summary and the trust row. This is the story the page is sold on.
class _LeadCard extends StatelessWidget {
  const _LeadCard({
    required this.story,
    required this.headline,
    required this.language,
    required this.strings,
    this.onTap,
    this.heroTag,
  });

  final Story story;
  final String headline;
  final String language;
  final AppStrings strings;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = story.imageUrl != null && story.imageUrl!.isNotEmpty;
    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                child: _Photo(
                  url: story.imageUrl!,
                  width: double.infinity,
                  height: 200,
                  heroTag: heroTag,
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.isBreaking || story.isDeveloping) ...[
                    _badgeRow(context),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    headline,
                    style: storyHeadline(context, headline, size: 22, maxLines: 4),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _Folio(story: story, strings: strings),
                  const SizedBox(height: 8),
                  Text(
                    story.lead,
                    style: teluguBody(context, story.lead, size: 14),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  _trustRow(context, strings, language),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeRow(BuildContext context) {
    return Row(
      children: [
        if (story.isBreaking)
          _Badge(label: strings.breaking, colour: SemanticColour.breaking),
        if (story.isDeveloping && !story.isBreaking) ...[
          _Badge(label: strings.developing, colour: SemanticColour.developing),
        ],
      ],
    );
  }

  Widget _trustRow(BuildContext context, AppStrings strings, String language) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _sourcesChip(context, story, strings),
        if (_evidenceChip(context, story, strings, language) case final chip?)
          chip,
        if (story.hasConflict)
          _chip(
            context,
            icon: Icons.warning_amber_rounded,
            label: strings.inConflict,
            colour: SemanticColour.disputed,
            filled: true,
          ),
        if (story.isCorrected)
          _chip(
            context,
            icon: Icons.edit_outlined,
            label: strings.corrections,
            colour: SemanticColour.developing,
          ),
      ],
    );
  }
}

/// A secondary story: column-width, square photo, three-line headline. Two of
/// these sit side by side under the lead.
class _SecondaryCard extends StatelessWidget {
  const _SecondaryCard({
    required this.story,
    required this.headline,
    required this.language,
    required this.strings,
    this.onTap,
    this.heroTag,
  });

  final Story story;
  final String headline;
  final String language;
  final AppStrings strings;
  final VoidCallback? onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = story.imageUrl != null && story.imageUrl!.isNotEmpty;
    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPhoto)
              _Photo(
                url: story.imageUrl!,
                width: double.infinity,
                height: 104,
                heroTag: heroTag,
              )
            else
              Container(
                height: 104,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (story.isBreaking || story.isDeveloping) ...[
                    _badgeRow(context),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    headline,
                    style: storyHeadline(context, headline, size: 15, maxLines: 3)
                        .copyWith(fontWeight: FontWeight.w700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  _Folio(story: story, strings: strings),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeRow(BuildContext context) {
    return Row(
      children: [
        if (story.isBreaking)
          _Badge(label: strings.breaking, colour: SemanticColour.breaking),
        if (story.isDeveloping && !story.isBreaking)
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
    required this.language,
    required this.strings,
    this.onTap,
  });

  final Story story;
  final String headline;
  final String language;
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
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Folio(story: story, strings: strings, brief: true),
                      const SizedBox(height: 5),
                      Text(
                        headline,
                        style: storyHeadline(context, headline, size: 15.5,
                                maxLines: 3)
                            .copyWith(fontWeight: FontWeight.w700),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (story.isCorroborated || story.hasConflict) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (story.isCorroborated)
                              _sourcesChip(context, story, strings),
                            if (story.isCorroborated && story.hasConflict)
                              const SizedBox(width: 6),
                            if (story.hasConflict)
                              _chip(
                                context,
                                icon: Icons.warning_amber_rounded,
                                label: strings.inConflict,
                                colour: SemanticColour.disputed,
                                filled: true,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.7,
            color: theme.dividerColor,
          ),
        ],
      ),
    );
  }
}

/// The pre-redesign card, for screens that have not been re-laid-out.
class _StandardCard extends StatelessWidget {
  const _StandardCard({
    required this.story,
    required this.headline,
    required this.language,
    required this.strings,
    required this.showImage,
    this.trailing,
    this.onTap,
  });

  final Story story;
  final String headline;
  final String language;
  final AppStrings strings;
  final bool showImage;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _CardShell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (story.isBreaking)
                              _Badge(
                                  label: strings.breaking,
                                  colour: SemanticColour.breaking),
                            if (story.isDeveloping && !story.isBreaking)
                              _Badge(
                                  label: strings.developing,
                                  colour: SemanticColour.developing),
                            _Folio(story: story, strings: strings),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    headline,
                    style: storyHeadline(context, headline, size: 16)
                        .copyWith(fontWeight: FontWeight.w700),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (story.place != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.place_outlined,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            story.place!,
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _sourcesChip(context, story, strings),
                      if (_evidenceChip(context, story, strings, language)
                          case final chip?)
                        chip,
                      if (story.hasConflict)
                        _chip(
                          context,
                          icon: Icons.warning_amber_rounded,
                          label: strings.inConflict,
                          colour: SemanticColour.disputed,
                          filled: true,
                        ),
                      if (story.isCorrected)
                        _chip(
                          context,
                          icon: Icons.edit_outlined,
                          label: strings.corrections,
                          colour: SemanticColour.developing,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (showImage &&
                story.imageUrl != null &&
                story.imageUrl!.isNotEmpty) ...[
              const SizedBox(width: 12),
              _Photo(url: story.imageUrl!, width: 96, height: 96, radius: 10),
            ],
          ],
        ),
      ),
    );
  }
}
