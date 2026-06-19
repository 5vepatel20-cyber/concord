// Color scheme assembled from brand tokens (BRAND.md).
// Severity ramp is separate — see SeverityColors in tokens.dart.

import 'package:flutter/material.dart';
import 'tokens.dart';

ColorScheme buildConcordColorScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: BrandColors.concordBlue,
    onPrimary: Neutrals.surface,
    primaryContainer: BrandColors.concordBlueTint,
    onPrimaryContainer: BrandColors.concordBluePressed,
    secondary: Neutrals.body,
    onSecondary: Neutrals.surface,
    secondaryContainer: Neutrals.mist,
    onSecondaryContainer: Neutrals.ink,
    tertiary: SeverityColors.moderate,
    onTertiary: Neutrals.surface,
    tertiaryContainer: Color(0xFFFBE6DD),
    onTertiaryContainer: Neutrals.ink,
    error: SeverityColors.severe,
    onError: Neutrals.surface,
    errorContainer: Color(0xFFFDEAEA),
    onErrorContainer: Neutrals.ink,
    surface: Neutrals.surface,
    onSurface: Neutrals.ink,
    surfaceContainerLowest: Neutrals.surface,
    surfaceContainerLow: Neutrals.mist,
    surfaceContainer: Neutrals.mist,
    surfaceContainerHigh: Neutrals.mist,
    surfaceContainerHighest: Neutrals.mist,
    onSurfaceVariant: Neutrals.slate,
    outline: Neutrals.hairline,
    outlineVariant: Neutrals.hairline,
    shadow: Color(0x1A0F1B2D),
    scrim: Color(0x660F1B2D),
    inverseSurface: Neutrals.ink,
    onInverseSurface: Neutrals.surface,
    inversePrimary: BrandColors.concordBlueTint,
  );
}
