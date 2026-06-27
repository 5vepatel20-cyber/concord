// Sign-in screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../theme/tokens.dart';
import 'auth_controller.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
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
        .signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    switch (res) {
      case Ok():
        // go_router redirect handles navigation on auth state change.
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
      appBar: AppBar(title: const Text('Sign in')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s5),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Welcome back', style: t.textTheme.displayLarge),
                const SizedBox(height: Space.s2),
                Text(
                  'Concord is not a medical device. Your data stays between you and your care team.',
                  style: t.textTheme.bodyMedium?.copyWith(
                    color: Neutrals.slate,
                  ),
                ),
                const SizedBox(height: Space.s6),
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
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: Space.s4),
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
                      : const Text('Sign in'),
                ),
                const SizedBox(height: Space.s3),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context.push('/forgot-password'),
                  child: const Text('Forgot password?'),
                ),
                const SizedBox(height: Space.s2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('No account?', style: t.textTheme.bodyMedium),
                    TextButton(
                      onPressed: _busy ? null : () => context.go('/sign-up'),
                      child: const Text('Create one'),
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
