// Smoke test for brand theme + severity chip rendering.

import 'package:concord/theme/theme_data.dart';
import 'package:concord/widgets/severity_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Severity ramp renders all 4 chips with labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: const Scaffold(
          body: Wrap(
            children: [
              SeverityChip(grade: 0),
              SeverityChip(grade: 1),
              SeverityChip(grade: 2),
              SeverityChip(grade: 3),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('None'), findsOneWidget);
    expect(find.text('Mild'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('Severe'), findsOneWidget);
  });

  testWidgets('SeverityChip asserts on out-of-range grade', (tester) async {
    expect(
      () => SeverityChip(grade: -1),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => SeverityChip(grade: 4),
      throwsA(isA<AssertionError>()),
    );
  });
}
