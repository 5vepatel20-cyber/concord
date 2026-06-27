import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/monitoring/posthog_init.dart';
import '../theme/tokens.dart';
import 'download_utils.dart';

class ShareCard extends StatelessWidget {
  const ShareCard({
    super.key,
    required this.summary,
    required this.docType,
    required this.criticalFlagCount,
  });

  final String summary;
  final String docType;
  final int criticalFlagCount;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final summarySnippet = summary.length > 160
        ? '${summary.substring(0, 157)}...'
        : summary;

    return Container(
      width: 400,
      padding: const EdgeInsets.all(Space.s5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            t.colorScheme.surface,
            t.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: Neutrals.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.medical_services_outlined,
                size: 20,
                color: t.colorScheme.primary,
              ),
              const SizedBox(width: Space.s1),
              Text(
                'Concord',
                style: t.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: t.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(
            'I decoded my medical report with Concord',
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.s2),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s2,
              vertical: Space.s1,
            ),
            decoration: BoxDecoration(
              color: t.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
            child: Text(
              docType,
              style: t.textTheme.labelSmall?.copyWith(
                color: t.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            summarySnippet,
            style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
          ),
          if (criticalFlagCount > 0) ...[
            const SizedBox(height: Space.s2),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: SeverityColors.moderate,
                ),
                const SizedBox(width: Space.s1),
                Text(
                  '$criticalFlagCount flag${criticalFlagCount == 1 ? '' : 's'} found',
                  style: t.textTheme.bodySmall?.copyWith(
                    color: SeverityColors.moderate,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.s4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: Space.s2),
            decoration: BoxDecoration(
              color: t.colorScheme.primary,
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Text(
              'Decode your report at concord.so',
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(
                color: t.colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ShareCardController {
  final GlobalKey repaintKey = GlobalKey();

  Future<Uint8List?> captureToPng() async {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> downloadPng() async {
    final bytes = await captureToPng();
    if (bytes == null) return;

    capturePosthogEvent('share_card_downloaded');
    downloadBytes(bytes, 'concord-decode.png');
  }
}
