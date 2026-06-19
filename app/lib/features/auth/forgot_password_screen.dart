// Forgot-password screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../theme/tokens.dart';
import 'auth_controller.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(email: _email.text);
    if (!mounted) return;
    switch (res) {
      case Ok():
        setState(() => _sent = true);
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
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s5),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reset your password', style: t.textTheme.displayLarge),
                const SizedBox(height: Space.s2),
                Text(
                  _sent
                      ? 'Check your email. We sent a reset link if an account exists for that address.'
                      : 'Enter the email you used to sign up. We\'ll send a reset link.',
                  style: t.textTheme.bodyMedium?.copyWith(color: Neutrals.slate),
                ),
                const SizedBox(height: Space.s6),
                if (!_sent) ...[
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.s3),
                    Text(_error!,
                        style: t.textTheme.bodySmall?.copyWith(color: SeverityColors.severe)),
                  ],
                  const SizedBox(height: Space.s5),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send reset link'),
                  ),
                ],
                const SizedBox(height: Space.s3),
                TextButton(
                  onPressed: () => context.go('/sign-in'),
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
