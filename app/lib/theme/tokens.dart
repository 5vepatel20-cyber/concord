// Concord design tokens (BRAND.md). Raw values; do not use directly in widgets —
// import colors.dart / typography.dart / theme_data.dart instead.

import 'package:flutter/material.dart';

/// Brand colors (BRAND.md §3.1).
class BrandColors {
  const BrandColors._();
  static const Color concordBlue = Color(0xFF1668E0);
  static const Color concordBluePressed = Color(0xFF0F4FB0);
  static const Color concordBlueTint = Color(0xFFEAF1FD);
}

/// Neutrals (BRAND.md §3.2).
class Neutrals {
  const Neutrals._();
  static const Color ink = Color(0xFF0F1B2D);
  static const Color body = Color(0xFF2B3A4F);
  static const Color slate = Color(0xFF5E6B7E);
  static const Color hint = Color(0xFF9AA6B6);
  static const Color mist = Color(0xFFF4F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color hairline = Color(0xFFE2E8F0);
}

/// PRO-CTCAE severity ramp (BRAND.md §3.3). Never color-only — always pair with label.
class SeverityColors {
  const SeverityColors._();
  static const Color none = Color(0xFF16A974); // grade 0
  static const Color mild = Color(0xFFE8A33D); // grade 1
  static const Color moderate = Color(0xFFF2683C); // grade 2
  static const Color severe = Color(0xFFE5484D); // grade 3

  static Color byGrade(int g) {
    if (g <= 0) return none;
    if (g == 1) return mild;
    if (g == 2) return moderate;
    return severe;
  }

  static String labelByGrade(int g) {
    if (g <= 0) return 'None';
    if (g == 1) return 'Mild';
    if (g == 2) return 'Moderate';
    return 'Severe';
  }
}

/// 4-pt spacing grid (BRAND.md §5).
class Space {
  const Space._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
}

/// Radii (BRAND.md §5).
class Radii {
  const Radii._();
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
}

/// Motion (BRAND.md §9).
class Motion {
  const Motion._();
  static const Duration chip = Duration(milliseconds: 80);
  static const Duration ui = Duration(milliseconds: 240);
  static const Duration hero = Duration(milliseconds: 400);
  static const Duration severityPulse = Duration(milliseconds: 1200);
  static const Curve ease = Cubic(0.2, 0.8, 0.2, 1);
}
