import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../models/story.dart';
import '../state/app_state.dart';

/// A full-bleed vertical pager of short-form cards.
///
/// Each card is a published story rendered large: headline, place, evidence
/// tag and source count. The card is not a video player -- the newsroom
/// generates a poster plus a read-aloud track, so the card plays its audio
/// while the reader reads the headline.
class ShortsPager extends StatelessWidget {
  const ShortsPager({
    super.key,
    required this.controller,
    required this.stories,
    required this.onOpenStory,
  });

  final PageController controller;
  final List<Story> stories;
  final ValueChanged<Story> onOpenStory;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      itemCount: stories.length,
      itemBuilder: (context, index) {
        final story = stories[index];
        return _ShortCard(story: story, onTap: () => onOpenStory(story));
      },
    );
  }
}

class _ShortCard extends StatelessWidget {
  const _ShortCard({required this.story, required this.onTap});

  final Story story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final strings = app.strings;
    final theme = Theme.of(context);
    final headline = story.headline(app.locale);
    final hasImage = story.imageUrl != null;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            CachedNetworkImage(
              imageUrl: story.imageUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (context, url, error) =>
                  Container(color: theme.colorScheme.surfaceContainerHighest),
            )
          else
            Container(color: theme.colorScheme.surfaceContainerHigh),
          // A gradient carries the photograph, but a gradient cannot be
          // trusted with type: white text over an arbitrary photograph needs
          // a ground at or below 0.18 relative luminance, which no partial
          // scrim reaches. The type sits on a near-opaque panel instead, so
          // the ratio holds whatever the newsroom's picture is.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.4, 0.75, 1.0],
                colors: [
                  Color(0x8C000000),
                  Color(0x00000000),
                  Color(0x99000000),
                  Color(0xE6000000),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (story.isBreaking)
                        _tag(context, strings.breaking,
                            SemanticColour.breaking.badge),
                      if (story.isDeveloping && !story.isBreaking)
                        _tag(context, strings.developing,
                            SemanticColour.developing.badge),
                      const Spacer(),
                      if (story.hasAudio)
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(
                            color: Color(0xCC000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.headphones_rounded,
                              color: Colors.white, size: 18),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xE6000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (story.place != null) ...[
                          Row(
                            children: [
                              const Icon(Icons.place_rounded,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  story.place!,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          headline,
                          style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                height: hasTeluguScript(headline) ? 1.38 : 1.26,
                              ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _chip(strings.sources,
                                story.numSources.toString()),
                            const SizedBox(width: 8),
                            _chip(
                                strings.reading,
                                '${readingTime(story.body(app.locale))} '
                                    '${strings.minRead}'),
                            const Spacer(),
                            Text(
                              relativeTime(story.publishedAt,
                                  strings: strings),
                              style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String label, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x38FFFFFF),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
