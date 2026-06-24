import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/document_repository.dart';
import '../../theme/tokens.dart';

class DocumentDecodeScreen extends ConsumerStatefulWidget {
  const DocumentDecodeScreen({super.key});

  @override
  ConsumerState<DocumentDecodeScreen> createState() =>
      _DocumentDecodeScreenState();
}

class _DocumentDecodeScreenState extends ConsumerState<DocumentDecodeScreen> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  File? _selectedImage;
  bool _isLoading = false;
  DocumentDecodeResult? _result;
  String? _error;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xfile = await _picker.pickImage(source: ImageSource.camera);
    if (xfile != null) {
      setState(() => _selectedImage = File(xfile.path));
    }
  }

  Future<void> _pickGallery() async {
    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile != null) {
      setState(() => _selectedImage = File(xfile.path));
    }
  }

  Future<void> _decode() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Paste or type the medical text to decode.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final repo = ref.read(documentRepositoryProvider);
      final result = await repo.decode(ocrText: text);
      setState(() {
        _result = result;
        _isLoading = false;
      });
    } catch (e) {
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
          if (_selectedImage != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _selectedImage = null),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedImage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: Image.file(
                      _selectedImage!,
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
