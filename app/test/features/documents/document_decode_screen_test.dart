import 'package:concord/data/repositories/document_repository.dart';
import 'package:concord/data/supabase/supabase_provider.dart';
import 'package:concord/features/documents/document_decode_screen.dart';
import 'package:concord/theme/theme_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../mocks.dart';

final sampleResult = DocumentDecodeResult(
  documentId: 'test-doc-1',
  summary: 'Patient labs are within normal limits.',
  extraction: {
    'doc_type': 'Lab Result',
    'summary': 'Patient labs are within normal limits.',
    'extracted_labs': [
      {
        'name': 'WBC',
        'value': '6.5',
        'unit': 'K/uL',
        'reference_range': '4.0-11.0',
        'flag': 'normal',
      },
    ],
    'medications': ['Lisinopril 10mg'],
    'diagnoses': ['Hypertension'],
    'suggested_questions': ['Should I continue my current dosage?'],
    'critical_flags': [],
  },
);

final resultWithFlags = DocumentDecodeResult(
  documentId: 'test-doc-2',
  summary: 'Critical findings detected.',
  extraction: {
    'doc_type': 'Lab Result',
    'summary': 'Critical findings detected.',
    'extracted_labs': [],
    'medications': [],
    'diagnoses': [],
    'suggested_questions': [],
    'critical_flags': [
      'Hemoglobin critically low at 6.2 g/dL',
      'Immediate transfusion recommended',
    ],
  },
);

Widget buildApp({
  DocumentDecodeResult? decodeResult,
  Object Function()? decodeThrows,
  required SupabaseClient supabaseClient,
}) {
  final mockRepo = MockDocumentRepository();
  mockRepo.mockDecodeAnonymously = decodeResult;
  if (decodeThrows != null) mockRepo.mockDecodeAnonymouslyThrows = decodeThrows;

  final router = GoRouter(
    initialLocation: '/documents/decode',
    routes: [
      GoRoute(
        path: '/documents/decode',
        builder: (_, __) => const DocumentDecodeScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (_, __) => const Scaffold(body: Text('Sign Up')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      documentRepositoryProvider.overrideWithValue(mockRepo),
      supabaseClientProvider.overrideWithValue(supabaseClient),
    ],
    child: MaterialApp.router(theme: buildConcordTheme(), routerConfig: router),
  );
}

SupabaseClient createSupabaseClient() {
  return SupabaseClient(
    'https://test.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE5ODAsImV4cCI6MTk4MX0.test',
  );
}

void main() {
  group('initial state', () {
    testWidgets('renders text field and decode button', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(buildApp(supabaseClient: supabaseClient));
        await tester.pumpAndSettle();

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Decode with AI'), findsOneWidget);
        expect(find.text('Camera'), findsOneWidget);
        expect(find.text('Gallery'), findsOneWidget);
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('validation', () {
    testWidgets('shows error when decode tapped with no text', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(buildApp(supabaseClient: supabaseClient));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        expect(
          find.text('Paste medical text or take a photo to decode.'),
          findsOneWidget,
        );
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('successful decode', () {
    testWidgets('shows result card after successful decode', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(
          buildApp(decodeResult: sampleResult, supabaseClient: supabaseClient),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Patient has normal blood work. Hb 14.2, WBC 6.5.',
        );
        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        expect(find.text('AI Decode Result'), findsOneWidget);
        expect(
          find.text('Patient labs are within normal limits.'),
          findsWidgets,
        );
        expect(find.text('Lisinopril 10mg'), findsOneWidget);
        expect(
          find.text('Should I continue my current dosage?'),
          findsOneWidget,
        );
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('shows signup prompt for anonymous users', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(
          buildApp(decodeResult: sampleResult, supabaseClient: supabaseClient),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Patient has normal blood work.',
        );
        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        expect(find.text('Track symptoms over time'), findsOneWidget);
        expect(find.text('Create free account'), findsOneWidget);
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('tapping signup prompt navigates to sign-up', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(
          buildApp(decodeResult: sampleResult, supabaseClient: supabaseClient),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Patient has normal blood work.',
        );
        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Create free account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create free account'));
        await tester.pumpAndSettle();

        expect(find.text('Sign Up'), findsOneWidget);
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('error state', () {
    testWidgets('shows error message when decode fails', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(
          buildApp(
            decodeThrows: () => Exception('AI service unavailable'),
            supabaseClient: supabaseClient,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField),
          'Patient has normal blood work.',
        );
        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        expect(find.textContaining('AI service unavailable'), findsOneWidget);
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('critical flags', () {
    testWidgets('displays critical flags section when present', (tester) async {
      final supabaseClient = createSupabaseClient();
      try {
        await tester.pumpWidget(
          buildApp(
            decodeResult: resultWithFlags,
            supabaseClient: supabaseClient,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Hb critically low.');
        await tester.tap(find.text('Decode with AI'));
        await tester.pumpAndSettle();

        expect(find.text('Critical Flags'), findsOneWidget);
        expect(
          find.textContaining('Hemoglobin critically low'),
          findsOneWidget,
        );
        expect(find.textContaining('Immediate transfusion'), findsOneWidget);
      } finally {
        supabaseClient.auth.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
