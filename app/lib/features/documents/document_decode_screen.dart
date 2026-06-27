import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/monitoring/posthog_init.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/supabase/supabase_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/share_card.dart';

class DocumentDecodeScreen extends ConsumerStatefulWidget {
  const DocumentDecodeScreen({super.key});

  @override
  ConsumerState<DocumentDecodeScreen> createState() =>
      _DocumentDecodeScreenState();
}

class _DocumentDecodeScreenState extends ConsumerState<DocumentDecodeScreen> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageBase64;
  bool _isLoading = false;
  DocumentDecodeResult? _result;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  static const _maxImageBytes = 10 * 1024 * 1024;

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.camera);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        setState(
          () => _error = 'Image is too large. Please use an image under 10 MB.',
        );
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _pickGallery() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile != null) {
      final bytes = await xfile.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        setState(
          () => _error = 'Image is too large. Please use an image under 10 MB.',
        );
        return;
      }
      setState(() {
        _imageBytes = bytes;
        _imageBase64 = base64Encode(bytes);
      });
    }
  }

  Future<void> _decode() async {
    final text = _textController.text.trim();
    if (text.isEmpty && _imageBase64 == null) {
      setState(() => _error = 'Paste medical text or take a photo to decode.');
      return;
    }
    if (text.length < 10 && _imageBase64 == null) {
      setState(
        () =>
            _error = 'Please provide at least 10 characters or a clear photo.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    capturePosthogEvent(
      'decode_started',
      properties: {
        'char_length': text.length,
        'has_image': _imageBase64 != null,
      },
    );

    try {
      final repo = ref.read(documentRepositoryProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      final isAnon = session == null;
      final result = isAnon
          ? await repo.decodeAnonymously(
              ocrText: text,
              imageBase64: _imageBase64,
            )
          : await repo.decode(ocrText: text, imageBase64: _imageBase64);
      if (!mounted) return;
      capturePosthogEvent(
        'decode_completed',
        properties: {
          'is_anon': isAnon,
          'char_length': text.length,
          'has_image': _imageBase64 != null,
        },
      );
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      capturePosthogEvent(
        'decode_errored',
        properties: {
          'error': e.runtimeType.toString(),
          'char_length': text.length,
        },
      );
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
    if (text.length < 10 && _imageBase64 == null) {
      setState(
        () =>
            _error = 'Please provide at least 10 characters or a clear photo.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    capturePosthogEvent(
      'decode_started',
      properties: {
        'char_length': text.length,
        'has_image': _imageBase64 != null,
      },
    );

    try {
      final repo = ref.read(documentRepositoryProvider);
      final session = ref.read(supabaseClientProvider).auth.currentSession;
      final isAnon = session == null;
      final result = isAnon
          ? await repo.decodeAnonymously(
              ocrText: text,
              imageBase64: _imageBase64,
            )
          : await repo.decode(ocrText: text, imageBase64: _imageBase64);
      capturePosthogEvent(
        'decode_completed',
        properties: {
          'is_anon': isAnon,
          'char_length': text.length,
          'has_image': _imageBase64 != null,
        },
      );
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
      capturePosthogEvent(
        'decode_errored',
        properties: {
          'error': e.runtimeType.toString(),
          'char_length': text.length,
        },
      );
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Decode Document'),
        actions: [
          if (_imageBytes != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _imageBytes = null;
                _imageBase64 = null;
              }),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_imageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Image.memory(
                      _imageBytes!,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                  const SizedBox(width: Space.s2),
                  OutlinedButton.icon(
                    onPressed: _pickGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                  ),
                ],
              ),

              const SizedBox(height: Space.s4),

              Text(
                'Or paste the medical text below:',
                style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
              ),
              const SizedBox(height: Space.s2),
              TextField(
                controller: _textController,
                maxLines: 10,
                maxLength: 50000,
                decoration: const InputDecoration(
                  hintText:
                      'Paste discharge summary, lab results, or visit notes...',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: Space.s4),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isLoading ? null : _decode,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Decode with AI'),
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s4),
                  child: Container(
                    padding: const EdgeInsets.all(Space.s3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                ),

              if (_result != null) ...[
                const SizedBox(height: Space.s5),
                _ResultCard(result: _result!),
                const SizedBox(height: Space.s4),
                _ShareAction(result: _result!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final DocumentDecodeResult result;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AI Decode Result',
          style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Space.s3),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FD),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Document Type',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                result.docType,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.s4),

        Text(
          'Summary',
          style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: Space.s1),
        Text(result.summary, style: t.textTheme.bodyMedium),

        if (result.criticalFlags.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Space.s3),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Critical Flags',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: Space.s1),
                for (final flag in result.criticalFlags)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '⚠ ',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                        Expanded(
                          child: Text(
                            flag,
                            style: TextStyle(color: Colors.red.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        if (result.extractedLabs.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Text(
            'Lab Values',
            style: t.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.s2),
          for (final lab in result.extractedLabs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(Space.s3),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lab['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${lab['value'] ?? ''} ${lab['unit'] ?? ''}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  if (lab['flag'] != null) ...[
                    const SizedBox(width: Space.s2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: lab['flag'] == 'normal'
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        (lab['flag'] as String).replaceAll('_', ' '),
                        style: TextStyle(
                          fontSize: 11,
                          color: lab['flag'] == 'normal'
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],

        if (result.medications.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Text(
            'Medications Mentioned',
            style: t.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.s1),
          for (final med in result.medications)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.medication,
                    size: 16,
                    color: Colors.blueGrey,
                  ),
                  const SizedBox(width: Space.s1),
                  Text(med),
                ],
              ),
            ),
        ],

        if (result.suggestedQuestions.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          Text(
            'Questions for Your Care Team',
            style: t.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: Space.s1),
          for (final q in result.suggestedQuestions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(q)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ShareAction extends ConsumerStatefulWidget {
  const _ShareAction({required this.result});

  final DocumentDecodeResult result;

  @override
  ConsumerState<_ShareAction> createState() => _ShareActionState();
}

class _ShareActionState extends ConsumerState<_ShareAction> {
  final _controller = ShareCardController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return Column(
      children: [
        RepaintBoundary(
          key: _controller.repaintKey,
          child: ShareCard(
            summary: widget.result.summary,
            docType: widget.result.docType,
            criticalFlagCount: widget.result.criticalFlags.length,
          ),
        ),
        const SizedBox(height: Space.s3),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _onShare,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined, size: 18),
            label: Text(_saving ? 'Generating...' : 'Download share image'),
          ),
        ),
      ],
    );
  }

  Future<void> _onShare() async {
    setState(() => _saving = true);
    try {
      await _controller.downloadPng();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share image downloaded.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate share image.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
