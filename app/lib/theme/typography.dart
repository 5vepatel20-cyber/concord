// Typography (BRAND.md §4). Family: Inter. Tabular numerals for clinical data.

import 'package:flutter/material.dart';

const String _fontFamily = 'Inter';

TextTheme buildConcordTextTheme() {
  // BRAND.md §4.1 scale. Weight rules (§4.2): 400 default, 600 emphasis, never 700.
  return const TextTheme(
    displayLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 32,
      height: 40 / 32,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    displayMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 28,
      height: 36 / 28,
      fontWeight: FontWeight.w600,
    ),
    headlineLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 24,
      height: 32 / 24,
      fontWeight: FontWeight.w600,
    ),
    headlineMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 22,
      height: 30 / 22,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 20,
      height: 28 / 20,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 17,
      height: 24 / 17,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
    ),
    bodyMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
    ),
    bodySmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
    ),
    labelLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
    ),
    labelMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w500,
    ),
    labelSmall: TextStyle(
      // BRAND.md `micro` — 11/16, all-caps reserved for severity / status.
      fontFamily: _fontFamily,
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
    ),
  );
}

/// Numeric / clinical-data style. Tabular numerals ON. Use for grades, vitals, labs, %.
const TextStyle numericTextStyle = TextStyle(
  fontFamily: _fontFamily,
  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  fontWeight: FontWeight.w500,
);
