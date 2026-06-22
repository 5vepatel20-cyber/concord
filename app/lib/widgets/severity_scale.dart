import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'severity_chip.dart';

class SeverityScale extends StatelessWidget {
  const SeverityScale({
    super.key,
    required this.grades,
    required this.selectedGrade,
    required this.onChanged,
  });

  final List<int> grades;
  final int? selectedGrade;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.s2,
      runSpacing: Space.s2,
      children: [
        for (final g in grades)
          InkWell(
            onTap: () => onChanged(selectedGrade == g ? null : g),
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.all(Space.s1),
              child: SeverityChip(grade: g, outlined: selectedGrade != g),
            ),
          ),
      ],
    );
  }
}
