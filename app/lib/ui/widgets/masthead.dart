import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/theme.dart';

/// The paper's nameplate, drawn as one lockup so the splash screen, the front
/// page and the About card can never disagree about what the paper is called.
///
/// The nameplate is typeset rather than typed: the masthead rule is drawn
/// between the Telugu nameplate and the Latin folio line, the way a nameplate
/// sits on a front page, and the Latin line is tracked out the way a folio is.
class DashaMasthead extends StatelessWidget {
  const DashaMasthead({
    super.key,
    this.size = MastheadSize.front,
    this.onColour = true,
    this.align = TextAlign.center,
  });

  /// How big the lockup is drawn. `splash` fills a first frame; `front` sits
  /// above the feed; `compact` fits an app bar.
  final MastheadSize size;

  /// Whether the lockup sits on the masthead red or on the page surface. On
  /// the page surface the rule and the type are inked rather than reversed.
  final bool onColour;

  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final dims = _dims(size);
    final ink = onColour ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final rule = onColour
        ? Colors.white.withValues(alpha: 0.75)
        : Theme.of(context).colorScheme.outlineVariant;
    final folio =
        onColour ? Colors.white.withValues(alpha: 0.72) : ink.withValues(alpha: 0.62);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : align == TextAlign.right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
      children: [
        Text(
          teluguNameplate,
          textAlign: align,
          style: TextStyle(
            fontFamily: 'NotoSansTelugu',
            fontWeight: FontWeight.w800,
            fontSize: dims.nameplate,
            height: 1.2,
            color: ink,
            letterSpacing: dims.tracking,
          ),
        ),
        SizedBox(height: dims.gap),
        Container(
          width: dims.ruleWidth,
          height: dims.ruleThickness,
          color: rule,
        ),
        SizedBox(height: dims.gap),
        Text(
          latinNameplate,
          textAlign: align,
          style: TextStyle(
            fontFamily: 'DashaSerif',
            fontWeight: FontWeight.w700,
            fontSize: dims.folio,
            height: 1.0,
            color: folio,
            letterSpacing: dims.folioTracking,
          ),
        ),
      ],
    );
  }

  static _MastheadDims _dims(MastheadSize size) {
    switch (size) {
      case MastheadSize.splash:
        return const _MastheadDims(
          nameplate: 40,
          folio: 12.5,
          gap: 10,
          ruleThickness: 2,
          ruleWidth: 198,
          tracking: 0.4,
          folioTracking: 4.2,
        );
      case MastheadSize.front:
        return const _MastheadDims(
          nameplate: 27,
          folio: 10,
          gap: 7,
          ruleThickness: 1.6,
          ruleWidth: 132,
          tracking: 0.3,
          folioTracking: 3.4,
        );
      case MastheadSize.compact:
        return const _MastheadDims(
          nameplate: 18,
          folio: 7.5,
          gap: 4,
          ruleThickness: 1.2,
          ruleWidth: 88,
          tracking: 0.2,
          folioTracking: 2.6,
        );
    }
  }
}

/// Where the masthead is drawn, which is what its size means.
enum MastheadSize { splash, front, compact }

class _MastheadDims {
  const _MastheadDims({
    required this.nameplate,
    required this.folio,
    required this.gap,
    required this.ruleThickness,
    required this.ruleWidth,
    required this.tracking,
    required this.folioTracking,
  });

  final double nameplate;
  final double folio;
  final double gap;
  final double ruleThickness;
  final double ruleWidth;
  final double tracking;
  final double folioTracking;
}

/// The paper's mark for small inline spots: the `దశ` monogram on the masthead
/// red, with its own rule beneath, as the launcher icon is drawn.
///
/// This replaced the single `డ` glyph that used to stand in for the brand —
/// `డ` is the first sound of the English transliteration, not of the paper's
/// own name.
class DashaMonogram extends StatelessWidget {
  const DashaMonogram({
    super.key,
    this.extent = 38,
    this.radius,
    this.onColour = false,
  });

  /// Side of the red tile, in logical px.
  final double extent;

  /// Tile corner radius. Defaults to a fifth of the extent, the proportion a
  /// rounded-square mark uses.
  final double? radius;

  /// When the monogram already sits on the masthead red the tile is not
  /// redrawn; only the white glyph is.
  final bool onColour;

  @override
  Widget build(BuildContext context) {
    final glyph = _MonogramGlyph(
      extent: extent,
      colour: Colors.white,
    );
    if (onColour) return glyph;
    return Container(
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? extent * 0.2),
        color: mastheadRed,
      ),
      child: Center(child: glyph),
    );
  }
}

/// The monogram alone: `దశ` over a rule, drawn from the glyph block so the
/// rule is sized to the ink rather than to the advance width.
///
/// The glyph block is wrapped in a [FittedBox] because Telugu matras are
/// metrically taller than Latin ascenders, and the tile is a fixed square: a
/// face whose ascent and descent are wider than expected must scale down into
/// the tile rather than overflow it.
class _MonogramGlyph extends StatelessWidget {
  const _MonogramGlyph({required this.extent, required this.colour});

  final double extent;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            teluguMonogram,
            style: TextStyle(
              fontFamily: 'NotoSansTelugu',
              fontWeight: FontWeight.w800,
              fontSize: extent * 0.5,
              height: 1.08,
              color: colour,
            ),
          ),
          SizedBox(height: extent * 0.045),
          Container(
            width: extent * 0.52,
            height: extent * 0.045,
            color: colour,
          ),
        ],
      ),
    );
  }
}

/// The folio line that sits under a masthead: the paper's tagline, or the
/// edition date when one is supplied.
class MastheadFolio extends StatelessWidget {
  const MastheadFolio({super.key, this.date});

  final String? date;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context, 'te');
    return Text(
      date ?? strings.tagline,
      style: TextStyle(
        fontFamily: 'DashaSerif',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: Colors.white.withValues(alpha: 0.72),
      ),
    );
  }
}
