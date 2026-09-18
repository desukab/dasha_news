/// The editor app's visual language.
///
/// Deliberately not the reader app: a newsroom tool should look like a tool.
/// High contrast, dense lists, and a red that reads as "act on this" only on
/// the things that need acting on.
library;

import 'package:flutter/material.dart';

const Color _ink = Color(0xFF1B1B1F);
const Color _paper = Color(0xFFFDF7F2);
const Color _accent = Color(0xFFB3261E);
const Color _muted = Color(0xFF6B6470);
const Color _line = Color(0xFFE3DDD4);
const Color _good = Color(0xFF1E6B4F);

Color statusColor(String status) {
  switch (status) {
    case 'published':
    case 'corrected':
      return _good;
    case 'breaking':
      return _accent;
    case 'held':
    case 'killed':
    case 'failed':
      return _accent;
    case 'unpublished':
    case 'archived':
      return _muted;
    default:
      return const Color(0xFF8A6D1F);
  }
}

Color evidenceColor(String level) {
  switch (level) {
    case 'fact':
    case 'official':
      return _good;
    case 'claim':
      return const Color(0xFF8A6D1F);
    case 'allegation':
    case 'disputed':
    case 'unverified':
      return _accent;
    default:
      return _muted;
  }
}

ThemeData editorTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF141417) : _paper;
  final onSurface = dark ? const Color(0xFFF1ECE6) : _ink;
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: brightness,
    surface: surface,
    onSurface: onSurface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        color: onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1D1D22) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: dark ? const Color(0xFF2C2C33) : _line),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    dividerTheme: DividerThemeData(color: dark ? const Color(0xFF2A2A30) : _line, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1D1D22) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textTheme: const TextTheme(
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.4),
      labelSmall: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
    ),
  );
}
