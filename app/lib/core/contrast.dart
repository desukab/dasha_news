/// WCAG contrast arithmetic, so the app's colour decisions are stated as
/// ratios rather than eyeballed.
///
/// A colour *looks* fine on the screen it was picked on and fails on every
/// other. The two numbers that do not move are the relative luminance and the
/// ratio between two colours, so those are what the palette is defined in: a
/// test asserts the ratio and the palette cannot drift back under the
/// threshold without somebody editing the constant.
///
/// The maths is WCAG 2.1 §1.4.3 — relative luminance from the sRGB channels,
/// then `(L1 + 0.05) / (L2 + 0.05)`, with the lighter colour first so the ratio
/// is always at least 1.
library;

import 'dart:math' show pow;

import 'package:flutter/material.dart';

/// Body text, and anything below 18px — or 14px bold. The threshold the
/// palette is built to clear.
const double contrastAa = 4.5;

/// Large text: 18px and up, or 14px bold and up. A headline clears this where
/// a folio line would not.
const double contrastAaLarge = 3.0;

/// Icons, hairlines and other graphics that carry meaning but are not type.
const double contrastGraphics = 3.0;

/// A ground for white badge type. Badge labels run at 10px, under the 14px-bold
/// point at which WCAG lowers the bar, so they are held to the body-text ratio
/// with headroom rather than to it.
const double contrastBadgeGround = 5.0;

/// WCAG relative luminance. Flutter ships [Color.computeLuminance], which is
/// the same curve; this is re-derived here so a test can check a colour that
/// is not yet a [Color] and so the source of the number is visible.
double relativeLuminance(Color colour) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(colour.r * 255.0) +
      0.7152 * channel(colour.g * 255.0) +
      0.0722 * channel(colour.b * 255.0);
}

/// The WCAG contrast ratio between two colours, always ≥ 1.
double contrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The opacity [foreground] would need over [ground] to read as [mix] — used
/// to reason about a translucent ink without recomputing the blend by hand.
Color blendOver(Color foreground, Color ground, double opacity) {
  return Color.alphaBlend(foreground.withValues(alpha: opacity), ground);
}

extension ContrastChecks on Color {
  /// Contrast ratio against [ground], always ≥ 1.
  double contrastOn(Color ground) => contrastRatio(this, ground);

  /// Whether this colour is legible as type on [ground].
  ///
  /// Pass [large: true] for 18px+ text or 14px+ bold, where WCAG lowers the bar
  /// to [contrastAaLarge].
  bool passesAaOn(Color ground, {bool large = false}) {
    return contrastOn(ground) >= (large ? contrastAaLarge : contrastAa);
  }

  /// Whether this colour is distinguishable as a graphic — an icon, a rule, a
  /// chip border — on [ground].
  bool passesGraphicsOn(Color ground) => contrastOn(ground) >= contrastGraphics;
}
