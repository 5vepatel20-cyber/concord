// SeverityChip — pill that pairs a PRO-CTCAE grade with its label and color.
// BRAND.md §3.3 hard rule: every severity color MUST be paired with the grade label.
// Color is a redundant cue, never the carrier.

import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class SeverityChip extends StatelessWidget {
  const SeverityChip({
    super.key,
    required this.grade,
    this.size = SeverityChipSize.regular,
    this.outlined = false,
  }) : assert(grade >= 0 && grade <= 3, 'grade must be 0..3');

  final int grade;
  final SeverityChipSize size;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final color = SeverityColors.byGrade(grade);
    final label = SeverityColors.labelByGrade(grade);
    final isSmall = size == SeverityChipSize.small;
    final padH = isSmall ? Space.s2 : Space.s3;
    final padV = isSmall ? Space.s1 : Space.s2;
    final radius = isSmall ? Radii.sm : Radii.md;

    // Severity ramp bg at 12% opacity per BRAND.md §6 (chip spec).
    final bg = outlined ? Neutrals.surface : color.withValues(alpha: 0.12);

    final border = outlined ? Border.all(color: color, width: 1) : null;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isSmall ? 6 : 8,
            height: isSmall ? 6 : 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: Space.s2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: isSmall ? 11 : 12,
              height: 16 / 12,
              fontWeight: FontWeight.w500,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

enum SeverityChipSize { regular, small }
