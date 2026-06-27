import 'package:concord/theme/theme_data.dart';
import 'package:concord/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Concord branding, doc type, and summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShareCard(
              summary: 'Patient labs are normal. No critical findings.',
              docType: 'Lab Result',
              criticalFlagCount: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Concord'), findsOneWidget);
    expect(
      find.text('I decoded my medical report with Concord'),
      findsOneWidget,
    );
    expect(find.text('Lab Result'), findsOneWidget);
    expect(
      find.text('Patient labs are normal. No critical findings.'),
      findsOneWidget,
    );
    expect(find.text('Decode your report at concord.so'), findsOneWidget);
  });

  testWidgets('renders critical flag count when flags > 0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: const ShareCard(
              summary: 'Critical values detected.',
              docType: 'Lab Result',
              criticalFlagCount: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 flags found'), findsOneWidget);
  });

  testWidgets('renders singular flag text when count is 1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: const ShareCard(
              summary: 'One critical flag.',
              docType: 'Visit Note',
              criticalFlagCount: 1,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 flag found'), findsOneWidget);
  });

  testWidgets('truncates summary longer than 160 characters', (tester) async {
    final longSummary = 'A ' * 100;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ShareCard(
              summary: longSummary,
              docType: 'Discharge Summary',
              criticalFlagCount: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('...'), findsOneWidget);
    expect(longSummary.length, greaterThan(160));
  });

  testWidgets('does not render flag text when count is 0', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildConcordTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: const ShareCard(
              summary: 'All clear.',
              docType: 'Imaging',
              criticalFlagCount: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('flag'), findsNothing);
  });
}
