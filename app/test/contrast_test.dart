import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dasha_news/core/contrast.dart';
import 'package:dasha_news/core/theme.dart';

/// The palette, stated as ratios rather than as eyeballed colours.
///
/// Every semantic hue serves three jobs — type on a light card, type on a dark
/// card, and a ground for white badge type — and each job has a different WCAG
/// bar. This holds all three per hue, so a value that drifts back under its
/// threshold fails the build instead of failing a reader. The numbers this
/// asserts were computed, not chosen: the previous dark-mode chips were as low
/// as 1.74:1 for an unverified tag a reader is being asked to trust.
void main() {
  group('ink on a light card', () {
    const ground = Color(0xFFFFFFFF);

    for (final hue in SemanticColour.values) {
      test('${hue.name} clears AA on white', () {
        expect(
          hue.inkLight.contrastOn(ground),
          greaterThanOrEqualTo(contrastAa),
          reason:
              '${hue.name} inkLight is ${hue.inkLight.contrastOn(ground).toStringAsFixed(2)}:1 '
              'on white; body text needs $contrastAa:1.',
        );
      });
    }
  });

  group('ink on a dark card', () {
    const ground = Color(0xFF1B2027);

    for (final hue in SemanticColour.values) {
      test('${hue.name} clears AA on the dark surface', () {
        expect(
          hue.inkDark.contrastOn(ground),
          greaterThanOrEqualTo(contrastAa),
          reason:
              '${hue.name} inkDark is ${hue.inkDark.contrastOn(ground).toStringAsFixed(2)}:1 '
              'on the dark card; body text needs $contrastAa:1.',
        );
      });
    }
  });

  group('badge grounds take white type', () {
    // Badge type is 10px — smaller than the 14px-bold point at which WCAG
    // lowers the bar — so every badge is held to the body-text ratio and
    // then some, in both modes.
    for (final hue in SemanticColour.values) {
      test('${hue.name} badge clears the small-type bar for white ink', () {
        final ratio = hue.badge.contrastOn(Colors.white);
        expect(
          ratio,
          greaterThanOrEqualTo(contrastBadgeGround),
          reason:
              '${hue.name} badge is $ratio:1 against white type; small badge type '
              'needs $contrastBadgeGround:1 to stay legible.',
        );
      });
    }
  });

  group('the masthead band', () {
    test('the paper tint reads on the lightest stop of the gradient', () {
      expect(
        mastheadPaper.contrastOn(mastheadRed),
        greaterThanOrEqualTo(contrastAa),
        reason: 'mastheadPaper is ${mastheadPaper.contrastOn(mastheadRed)}:1 '
            'on $mastheadRed; it must carry the folio line.',
      );
    });

    test('the paper tint reads on the darkest stop of the gradient', () {
      expect(
        mastheadPaper.contrastOn(mastheadRedDark),
        greaterThanOrEqualTo(contrastAa),
      );
    });

    test('the masthead rule is visible as a graphic', () {
      expect(
        mastheadRule.contrastOn(mastheadRed),
        greaterThanOrEqualTo(contrastGraphics),
      );
    });

    test('a faded white no longer passes as masthead type', () {
      // 3.26:1 today. This is the failure the opaque tint replaced: fading
      // white toward the red it sits on fades it toward the colour it must
      // contrast with. Kept as a regression bar so nobody reintroduces it.
      final faded = blendOver(Colors.white, mastheadRed, 0.72);
      expect(
        faded.contrastOn(mastheadRed),
        lessThan(contrastAa),
      );
    });
  });

  group('the surfaces the palette is resolved against', () {
    test('the dark card is what the dark inks are measured on', () {
      // inkDark is tuned to this specific surface. If the theme moves, the
      // ratios above silently stop describing what the reader sees.
      expect(AppTheme.dark().cardColor, const Color(0xFF1B2027));
    });

    test('the light card is white', () {
      expect(AppTheme.light().cardColor, const Color(0xFFFFFFFF));
    });
  });
}
