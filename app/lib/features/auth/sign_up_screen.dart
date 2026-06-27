// Sign-up screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../theme/tokens.dart';
import 'auth_controller.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  bool _consent = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_consent) {
      setState(
        () => _error = 'Please confirm the consent statement to continue.',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref
        .read(authControllerProvider.notifier)
        .signUp(
          email: _email.text,
          password: _password.text,
          fullName: _fullName.text,
        );
    if (!mounted) return;
    switch (res) {
      case Ok():
        // Auth state change triggers go_router redirect to /onboarding.
        break;
      case Err(:final error):
        setState(() => _error = error.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.s5),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create your account', style: t.textTheme.displayLarge),
                const SizedBox(height: Space.s2),
                Text(
                  'Concord is not a medical device. It captures symptoms for your oncology team and helps you stay on track between visits.',
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: Neutrals.slate,
                  ),
                ),
                const SizedBox(height: Space.s6),
                TextFormField(
                  controller: _fullName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: Space.s3),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: Space.s3),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Password (min 8 chars)',
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8)
                      return 'At least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: Space.s5),
                CheckboxListTile(
                  value: _consent,
                  onChanged: (v) => setState(() {
                    _consent = v ?? false;
                    if (_consent) _error = null;
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'I understand Concord is not a medical device and does not replace advice from my oncology care team.',
                    style: t.textTheme.bodyMedium,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.s3),
                  Text(
                    _error!,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: SeverityColors.severe,
                    ),
                  ),
                ],
                const SizedBox(height: Space.s5),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
                const SizedBox(height: Space.s3),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account?',
                      style: t.textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => context.go('/sign-in'),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
