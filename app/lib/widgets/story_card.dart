import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_strings.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/story.dart';
import '../state/app_state.dart';

/// One story in a list.
///
/// The card front-loads the editorial contract: what the claim's evidence
/// level is, how many outlets reported it, and whether they agree. A reader
/// should be able to tell a corroborated story from a single-source rumour
/// without opening it.
class StoryCard extends StatelessWidget {
  const StoryCard({
    super.key,
    required this.story,
    this.onTap,
    this.showImage = true,
    this.compact = false,
    this.trailing,
  });

  final Story story;
  final VoidCallback? onTap;
  final bool showImage;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final theme = Theme.of(context);
    final language = app.locale;
    final headline = story.headline(language);

    return Card(
      child: InkWell(
        onTap: onTap,
        customBorder: Theme.of(context).cardTheme.shape,
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
                        Expanded(child: _metaRow(context, strings)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      headline,
                      style: theme.textTheme.titleMedium?.copyWith(
                        height: hasTeluguScript(headline) ? 1.42 : 1.32,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!compact && story.place != null) ...[
                      const SizedBox(height: 6),
                      _placeRow(context, strings),
                    ],
                    const SizedBox(height: 8),
                    _trustRow(context, strings),
                  ],
                ),
              ),
              if (showImage && story.imageUrl != null) ...[
                const SizedBox(width: 12),
                _thumbnail(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(BuildContext context, AppStrings strings) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (story.isBreaking) _badge(context, strings.breaking, AppTheme.breaking),
        if (story.isDeveloping && !story.isBreaking)
          _badge(context, strings.developing, AppTheme.developing),
        Text(
          story.sectionLabel(context.read<AppState>().locale).toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 0.8,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
        ),
        Text(
          '· ${relativeTime(story.publishedAt, strings: strings)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _placeRow(BuildContext context, AppStrings strings) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.place_outlined,
            size: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            story.place!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _trustRow(BuildContext context, AppStrings strings) {
    // The strongest claim is the first ranked one; absent a fact list (the
    // feed endpoint omits facts) there is no claim to point at, so the chip
    // is simply not drawn rather than decorated with a guess.
    final ranked = [...story.facts]..sort((a, b) => a.rank.compareTo(b.rank));
    final strongest = ranked.isEmpty ? null : ranked.first;
    final evidenceLevel =
        strongest?.evidenceLevel ?? (story.evidenceScore >= 0.7 ? 'fact' : 'claim');
    final evidenceLabel = strongest?.label(context.read<AppState>().locale) ?? '';
    final chips = <Widget>[
      _chip(
        context,
        icon: story.isCorroborated ? Icons.verified_rounded : Icons.info_outline,
        label: '${story.numSources} ${strings.sources}',
        colour: story.isCorroborated ? AppTheme.fact : AppTheme.claim,
        filled: story.isCorroborated,
      ),
      if (evidenceLabel.isNotEmpty)
        _chip(
          context,
          icon: Icons.shield_outlined,
          label: evidenceLabel,
          colour: evidenceColor(evidenceLevel),
          filled: false,
        ),
      if (story.hasConflict)
        _chip(
          context,
          icon: Icons.warning_amber_rounded,
          label: strings.inConflict,
          colour: AppTheme.disputed,
          filled: true,
        ),
      if (story.isCorrected)
        _chip(
          context,
          icon: Icons.edit_outlined,
          label: strings.corrections,
          colour: AppTheme.developing,
          filled: false,
        ),
    ];

    return Wrap(spacing: 6, runSpacing: 4, children: chips);
  }

  Widget _badge(BuildContext context, String label, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              fontSize: 10,
            ),
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color colour,
    required bool filled,
  }) {
    final theme = Theme.of(context);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? colour.withValues(alpha: 0.14) : colour.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colour.withValues(alpha: filled ? 0.4 : 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: colour),
            const SizedBox(width: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      );
  }

  Widget _thumbnail(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: story.imageUrl!,
        width: compact ? 72 : 96,
        height: compact ? 72 : 96,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          width: compact ? 72 : 96,
          height: compact ? 72 : 96,
        ),
        errorWidget: (context, url, error) => const SizedBox.shrink(),
      ),
    );
  }
}
