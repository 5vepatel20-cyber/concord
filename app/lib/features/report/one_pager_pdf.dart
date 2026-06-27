import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../data/repositories/report_repository.dart';
import '../../theme/tokens.dart';

Future<Uint8List> buildOnePagerPdf(OnePagerReport report) async {
  final pdf = pw.Document(
    title: 'Concord Symptom Report',
    author: 'Concord',
    subject: '${report.periodDays}-day symptom summary',
  );

  final concordBlue = PdfColor.fromInt(0xFF1668E0);
  final concordBlueTint = PdfColor.fromInt(0xFFEAF1FD);
  final ink = PdfColor.fromInt(0xFF0F1B2D);
  final body = PdfColor.fromInt(0xFF2B3A4F);
  final slate = PdfColor.fromInt(0xFF5E6B7E);
  final hint = PdfColor.fromInt(0xFF9AA6B6);
  final surface = PdfColor.fromString('#FFFFFF');
  final hairline = PdfColor.fromInt(0xFFE2E8F0);

  final stable = PdfColor.fromInt(0xFF16A974);
  final caution = PdfColor.fromInt(0xFFE8A33D);
  final warn = PdfColor.fromInt(0xFFF2683C);
  final severe = PdfColor.fromInt(0xFFE5484D);

  PdfColor gradeColor(int g) {
    switch (g) {
      case 1:
        return caution;
      case 2:
        return warn;
      case 3:
        return severe;
      default:
        return stable;
    }
  }

  String pct(double v) => '${(v * 100).round()}%';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      header: (context) => pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: concordBlue, width: 2),
          ),
        ),
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Concord',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: concordBlue,
                  ),
                ),
                pw.Text(
                  'Understand your health',
                  style: pw.TextStyle(fontSize: 8, color: slate),
                ),
              ],
            ),
            pw.Text(
              'Symptom Report — ${report.periodDays}-day summary',
              style: pw.TextStyle(fontSize: 10, color: slate),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated ${report.generatedAt}',
                  style: pw.TextStyle(fontSize: 8, color: hint),
                ),
                pw.Text(
                  'Concord — understand your health',
                  style: pw.TextStyle(fontSize: 8, color: hint),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Concord is not a medical device. It helps you track symptoms '
              'between visits. Always follow your care team\'s guidance.',
              style: pw.TextStyle(
                fontSize: 7,
                color: hint,
                fontStyle: pw.FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      build: (context) => [
        // ── Title section ──
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 16),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Symptom Summary',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${report.periodDays}-day symptom trend report · Generated ${report.generatedAt}',
                style: pw.TextStyle(fontSize: 11, color: slate),
              ),
            ],
          ),
        ),

        // ── Symptom heatmap ──
        _sectionHeader('Symptom Heatmap'),
        pw.SizedBox(height: 8),
        if (report.heatmapRows.isNotEmpty) ...[
          // Legend
          pw.Row(
            children: [
              pw.Text(
                'Grade:  ',
                style: pw.TextStyle(fontSize: 8, color: slate),
              ),
              for (final g in [0, 1, 2, 3])
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 8),
                  child: pw.Row(
                    children: [
                      pw.Container(
                        width: 10,
                        height: 10,
                        decoration: pw.BoxDecoration(
                          color: gradeColor(g),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(2),
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 2),
                      pw.Text(
                        g == 0 ? 'None' : g.toString(),
                        style: pw.TextStyle(fontSize: 8, color: slate),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 6),
          // Table
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: body,
            ),
            cellStyle: pw.TextStyle(fontSize: 7, color: ink),
            headerDecoration: pw.BoxDecoration(color: concordBlueTint),
            cellAlignments: {0: pw.Alignment.centerLeft},
            columnWidths: {0: const pw.FixedColumnWidth(120)},
            headers: [
              'Symptom',
              ...report.heatmapRows.first.gradesByDate.keys.take(14),
            ],
            data: report.heatmapRows
                .map(
                  (r) => [
                    r.termName,
                    ...r.gradesByDate.entries
                        .take(14)
                        .map((e) => e.value == 0 ? '-' : e.value.toString()),
                  ],
                )
                .toList(),
          ),
        ] else
          pw.Text(
            'No symptom data for this period.',
            style: pw.TextStyle(fontSize: 10, color: hint),
          ),

        // ── Worst episodes ──
        pw.SizedBox(height: 16),
        _sectionHeader('Worst Episodes (top 3)'),
        pw.SizedBox(height: 6),
        if (report.worstEpisodes.isNotEmpty)
          ...report.worstEpisodes.map(
            (e) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 120,
                    child: pw.Text(
                      e.termName,
                      style: pw.TextStyle(fontSize: 9, color: ink),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      height: 14,
                      decoration: pw.BoxDecoration(
                        color: hairline,
                        borderRadius: pw.BorderRadius.all(
                          pw.Radius.circular(3),
                        ),
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: (e.grade / 3) * 100,
                          height: 14,
                          decoration: pw.BoxDecoration(
                            color: gradeColor(e.grade.round()),
                            borderRadius: pw.BorderRadius.all(
                              pw.Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    '${e.grade.toStringAsFixed(1)} avg',
                    style: pw.TextStyle(fontSize: 8, color: slate),
                  ),
                  pw.SizedBox(width: 4),
                  pw.Text(
                    '(${e.count}x)',
                    style: pw.TextStyle(fontSize: 8, color: hint),
                  ),
                ],
              ),
            ),
          )
        else
          pw.Text(
            'No moderate-severe episodes.',
            style: pw.TextStyle(fontSize: 10, color: hint),
          ),

        // ── New or Worsening ──
        pw.SizedBox(height: 16),
        _sectionHeader('New or Worsening Symptoms'),
        pw.SizedBox(height: 6),
        if (report.newOrWorsening.isNotEmpty)
          ...report.newOrWorsening.map(
            (n) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: pw.BoxDecoration(
                      color: n.direction == 'new' ? warn : caution,
                      borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Text(
                      n.direction == 'new' ? 'New' : 'Worsened',
                      style: pw.TextStyle(
                        fontSize: 7,
                        color: surface,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Text(
                    n.termName,
                    style: pw.TextStyle(fontSize: 9, color: ink),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    'Grade: ${n.priorAvgGrade.toStringAsFixed(1)} → ${n.currentAvgGrade.toStringAsFixed(1)}',
                    style: pw.TextStyle(fontSize: 8, color: slate),
                  ),
                ],
              ),
            ),
          )
        else
          pw.Text(
            'No new or worsening symptoms detected.',
            style: pw.TextStyle(fontSize: 10, color: hint),
          ),

        // ── Medication Adherence ──
        pw.SizedBox(height: 16),
        _sectionHeader('Medication Adherence'),
        pw.SizedBox(height: 6),
        if (report.medicationAdherence.byMedication.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: concordBlueTint,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              'Overall adherence: ${pct(report.medicationAdherence.overallPct)}',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: concordBlue,
              ),
            ),
          ),
          pw.SizedBox(height: 6),
          ...report.medicationAdherence.byMedication.map(
            (m) => pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: 120,
                    child: pw.Text(
                      m.displayName,
                      style: pw.TextStyle(fontSize: 9, color: ink),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Container(
                      height: 12,
                      decoration: pw.BoxDecoration(
                        color: hairline,
                        borderRadius: pw.BorderRadius.all(
                          pw.Radius.circular(3),
                        ),
                      ),
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Container(
                          width: m.adherencePct,
                          height: 12,
                          decoration: pw.BoxDecoration(
                            color: m.adherencePct >= 80
                                ? stable
                                : (m.adherencePct >= 50 ? caution : severe),
                            borderRadius: pw.BorderRadius.all(
                              pw.Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    '${m.taken}/${m.total}',
                    style: pw.TextStyle(fontSize: 8, color: slate),
                  ),
                ],
              ),
            ),
          ),
        ] else
          pw.Text(
            'No medication data.',
            style: pw.TextStyle(fontSize: 10, color: hint),
          ),

        // ── Vitals ──
        pw.SizedBox(height: 16),
        _sectionHeader('Vitals'),
        pw.SizedBox(height: 6),
        if (report.vitals.isNotEmpty) ...[
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: body,
            ),
            cellStyle: pw.TextStyle(fontSize: 8, color: ink),
            headerDecoration: pw.BoxDecoration(color: concordBlueTint),
            headers: [
              'Date',
              'Steps',
              'HR (bpm)',
              'Sleep (h)',
              'Weight (kg)',
              'BP (sys/dia)',
            ],
            data: report.vitals
                .take(7)
                .map(
                  (v) => [
                    v.date,
                    v.steps?.toString() ?? '-',
                    v.avgHrBpm?.toString() ?? '-',
                    v.sleepHours?.toStringAsFixed(1) ?? '-',
                    v.weightKg?.toStringAsFixed(1) ?? '-',
                    v.bpSysAvg != null ? '${v.bpSysAvg}/${v.bpDiaAvg}' : '-',
                  ],
                )
                .toList(),
          ),
        ] else
          pw.Text(
            'No vitals data for this period.',
            style: pw.TextStyle(fontSize: 10, color: hint),
          ),

        // ── AI Narrative ──
        if (report.narrative != null && report.narrative!.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _sectionHeader('AI Summary'),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: concordBlueTint,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Text(
              report.narrative!,
              style: pw.TextStyle(fontSize: 9, color: ink, lineSpacing: 1.3),
            ),
          ),
        ],
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _sectionHeader(String title) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFF4F7FA),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromInt(0xFF0F1B2D),
      ),
    ),
  );
}

Future<void> saveOrPrintPdf(OnePagerReport report) async {
  final pdf = await buildOnePagerPdf(report);

  if (kIsWeb) {
    await Printing.sharePdf(
      bytes: pdf,
      filename: 'concord-report-${report.periodDays}d.pdf',
    );
  } else {
    await Printing.sharePdf(
      bytes: pdf,
      filename: 'concord-report-${report.periodDays}d.pdf',
    );
  }
}
