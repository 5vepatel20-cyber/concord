// Assembled ThemeData. Single source of truth — every screen pulls from this.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

ThemeData buildConcordTheme() {
  final colorScheme = buildConcordColorScheme();
  final textTheme = buildConcordTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: Neutrals.mist,
    fontFamily: 'Inter',
    visualDensity: VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Neutrals.surface,
      foregroundColor: Neutrals.ink,
      surfaceTintColor: Neutrals.surface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.headlineSmall,
      shape: Border(bottom: BorderSide(color: Neutrals.hairline)),
    ),
    cardTheme: CardThemeData(
      color: Neutrals.surface,
      surfaceTintColor: Neutrals.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.lg),
        side: const BorderSide(color: Neutrals.hairline),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BrandColors.concordBlue,
        foregroundColor: Neutrals.surface,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: BrandColors.concordBlue,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: Neutrals.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: BrandColors.concordBlue,
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Neutrals.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: Neutrals.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: Neutrals.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: const BorderSide(color: BrandColors.concordBlue, width: 2),
      ),
      labelStyle: textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
      hintStyle: textTheme.bodyMedium?.copyWith(color: Neutrals.hint),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Neutrals.surface,
      indicatorColor: BrandColors.concordBlueTint,
      surfaceTintColor: Neutrals.surface,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelMedium?.copyWith(color: Neutrals.ink),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: BrandColors.concordBlue);
        }
        return const IconThemeData(color: Neutrals.slate);
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: Neutrals.hairline,
      thickness: 1,
      space: 1,
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: const ZoomPageTransitionsBuilder(),
      },
    ),
  );
}
