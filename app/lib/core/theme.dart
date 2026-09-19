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

  static const Color breaking = Color(0xFFC62828);
  static const Color developing = Color(0xFF1565C0);
  static const Color fact = Color(0xFF2E7D32);
  static const Color claim = Color(0xFFEF6C00);
  static const Color allegation = Color(0xFFAD1457);
  static const Color unverified = Color(0xFF6A1B9A);
  static const Color disputed = Color(0xFFC62828);

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

/// Colour used to tag a claim's evidence level, mirrored from the newsroom's
/// own `EvidenceLevel` taxonomy so the app and the backend never disagree.
Color evidenceColor(String? level) {
  switch ((level ?? '').toLowerCase()) {
    case 'fact':
    case 'official':
      return AppTheme.fact;
    case 'claim':
      return AppTheme.claim;
    case 'allegation':
      return AppTheme.allegation;
    case 'forecast':
    case 'opinion':
      return AppTheme.unverified;
    case 'unverified':
      return AppTheme.unverified;
    case 'disputed':
      return AppTheme.disputed;
    default:
      return AppTheme.claim;
  }
}
