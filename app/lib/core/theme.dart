library;

import 'package:flutter/material.dart';

import 'format.dart';

/// The masthead red and its dark shade, used for the front-page masthead band
/// and the monogram. Kept here rather than in the generated assets so a widget
/// can paint a matching ground without going to a bitmap.
const Color mastheadRed = Color(0xFFB3261E);
const Color mastheadRedDark = Color(0xFF7F1212);

/// The Telugu nameplate, as one constant so no screen retypes it and no
/// transcription drifts in.
const String teluguNameplate = 'దశ న్యూస్';
const String latinNameplate = 'DASHA NEWS';
const String teluguMonogram = 'దశ';

/// A headline style that picks its face from the script in front of it.
///
/// Telugu is set in Noto Sans Telugu; Latin and Tenglish in the serif the
/// nameplate uses. Sniffing the *text* rather than the language setting is
/// what makes a mixed Tenglish headline pick the right face, and what keeps
/// a Telugu headline in its own face when the reader's language is English.
TextStyle storyHeadline(
  BuildContext context,
  String text, {
  double size = 20,
  FontWeight weight = FontWeight.w800,
  int maxLines = 3,
}) {
  final telugu = hasTeluguScript(text);
  return Theme.of(context).textTheme.headlineSmall!.copyWith(
        fontFamily: telugu ? 'NotoSansTelugu' : 'DashaSerif',
        fontWeight: weight,
        fontSize: size,
        // Telugu matras need a taller line than Latin ascenders do.
        height: telugu ? 1.34 : 1.22,
        letterSpacing: telugu ? 0.0 : -0.2,
      );
}

/// Body copy in Telugu gets the Telugu face for the same reason; Tenglish and
/// English stay in the Material default, which is already a humanist sans.
TextStyle teluguBody(BuildContext context, String text,
    {double size = 14, FontWeight weight = FontWeight.w400}) {
  return Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontFamily: hasTeluguScript(text) ? 'NotoSansTelugu' : null,
        fontSize: size,
        fontWeight: weight,
        height: hasTeluguScript(text) ? 1.5 : 1.45,
      );
}

/// The Dasha News visual language.
///
/// Colour is the brand's only ornament: a newsprint red as the single accent,
/// a warm paper surface in light mode, and a true low-glare ink in dark mode.
/// Telugu script needs more vertical room than Latin, so body text carries an
/// explicit line height; without it the matras crowd the line above.

const Color _kSeed = Color(0xFFB3261E);

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _kSeed,
      brightness: Brightness.light,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFFBF8F4),
      cardColor: Colors.white,
      dividerColor: const Color(0xFFE4DED5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFFBF8F4),
        foregroundColor: Color(0xFF14181D),
        elevation: 0,
        scrolledUnderElevation: 0.6,
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _kSeed,
      brightness: Brightness.dark,
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFF12161B),
      cardColor: const Color(0xFF1B2027),
      dividerColor: const Color(0xFF2B323C),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF12161B),
        foregroundColor: Color(0xFFEDEAE4),
        elevation: 0,
        scrolledUnderElevation: 0.6,
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      }),
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: base.textTheme.labelMedium,
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(
        thickness: 0.8,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: base.textTheme.titleSmall,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: base.textTheme.bodyLarge,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        showUnselectedLabels: true,
      ),
    );
  }

  /// Body copy is set a little taller than the Material default; Telugu and
  /// Tenglish vowel signs extend well above and below the x-height and need
  /// the room to stay legible at small sizes.
  static TextTheme _textTheme(TextTheme base) {
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.28,
        letterSpacing: -0.2,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.3,
        letterSpacing: -0.15,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.32,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.34,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.36,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.52),
      bodySmall: base.bodySmall?.copyWith(height: 1.45),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

/// A semantic colour, resolved against the surface it is painted on.
///
/// The newsroom's evidence taxonomy is carried in colour — breaking, fact,
/// claim, dispute — and each hue has to serve as a chip label, an icon and a
/// badge ground. A single mid-tone cannot: a colour dark enough to read as
/// type on white paper is too dark to read on a dark card, and a colour light
/// enough for a dark card will not take white type on a badge. So each hue
/// ships as three values, each chosen to clear its WCAG threshold by
/// construction rather than by eye:
///
///   [inkLight] — type on a light card, ≥ 4.5:1 against `#FFFFFF`
///   [inkDark]  — type on a dark card,  ≥ 4.5:1 against `#1B2027`
///   [badge]    — a ground for white type, ≥ 5:1, since badge type is 10px
///
/// [contrast_test.dart] holds all three bars, so a value that drifts back
/// under its threshold fails the build instead of failing a reader.
///
/// `claim` is the one hue that had to move: `#EF6C00` on white is 3.08:1,
/// under the 4.5 body-text bar, so it is deepened to `#BA5400`. The rest kept
/// their light-mode values, which already cleared the bar, and gained a dark
/// twin — the dark-mode chips were the worst failures in the app, as low as
/// 1.74:1 for an unverified tag that a reader is being asked to trust.
enum SemanticColour {
  breaking(
    inkLight: Color(0xFFC62828),
    inkDark: Color(0xFFD76A6A),
    badge: Color(0xFFC62828),
  ),
  developing(
    inkLight: Color(0xFF1565C0),
    inkDark: Color(0xFF548ED1),
    badge: Color(0xFF1565C0),
  ),
  fact(
    inkLight: Color(0xFF2E7D32),
    inkDark: Color(0xFF5B995F),
    badge: Color(0xFF2E7D32),
  ),
  claim(
    inkLight: Color(0xFFBA5400),
    inkDark: Color(0xFFEF6C00),
    badge: Color(0xFFB55200),
  ),
  allegation(
    inkLight: Color(0xFFAD1457),
    inkDark: Color(0xFFCC6D96),
    badge: Color(0xFFAD1457),
  ),
  unverified(
    inkLight: Color(0xFF6A1B9A),
    inkDark: Color(0xFFA87AC4),
    badge: Color(0xFF6A1B9A),
  ),
  disputed(
    inkLight: Color(0xFFC62828),
    inkDark: Color(0xFFD76A6A),
    badge: Color(0xFFC62828),
  );

  const SemanticColour({
    required this.inkLight,
    required this.inkDark,
    required this.badge,
  });

  final Color inkLight;
  final Color inkDark;
  final Color badge;

  /// Ink for the surface the reader is looking at.
  Color ink(Brightness brightness) =>
      brightness == Brightness.light ? inkLight : inkDark;

  /// Ink for the surface in front of the caller. Prefer this over passing
  /// [Brightness] around; it keeps the resolution at the paint site.
  Color inkOf(BuildContext context) => ink(Theme.of(context).brightness);
}

/// Type and ground colours for the masthead band.
///
/// These are opaque, not alpha-faded. A white at 0.72 over the masthead red is
/// 3.26:1 — under the body-text bar and visibly washed out — because fading
/// white toward the red it sits on fades it toward the colour it must contrast
/// with. A warm paper tint at full opacity is 6.17:1 on the *lightest* stop of
/// the gradient, so it holds across the whole band.
const Color mastheadPaper = Color(0xFFFFF7F2);
const Color mastheadRule = Color(0xFFFFF7F2);

/// A white tint translucent enough to still be a ground for white type on the
/// masthead red. This is the one place alpha is allowed on the band, and only
/// at this strength: `0x3DFFFFFF` — the obvious `white24` — fades to 4.23:1,
/// under the body-text bar, because fading white toward the red it sits on
/// fades it toward the colour it must contrast with.
const Color mastheadChip = Color(0x24FFFFFF);

/// The hue a claim's evidence level is painted in, mirrored from the
/// newsroom's own `EvidenceLevel` taxonomy so the app and the backend never
/// disagree.
///
/// Returns the token rather than a [Color]: the same level may be an ink on a
/// light card and an icon on a dark one, and the caller is the one holding the
/// [BuildContext] that decides which.
SemanticColour evidenceColour(String? level) {
  switch ((level ?? '').toLowerCase()) {
    case 'fact':
    case 'official':
      return SemanticColour.fact;
    case 'allegation':
      return SemanticColour.allegation;
    case 'forecast':
    case 'opinion':
    case 'unverified':
      return SemanticColour.unverified;
    case 'disputed':
      return SemanticColour.disputed;
    case 'claim':
    default:
      return SemanticColour.claim;
  }
}
