import 'package:flutter/material.dart';

import '../account_api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A new account with a password. Passkeys come right after, from the home
/// screen.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).signUp(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
      // Signed in: the home screen is under this one.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
      ),
      body: GlowBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, kToolbarHeight + 8, 24, 24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create your account',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Start with a password. Then add a passkey, and sign in '
                    'with Face ID from then on.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Palette.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    onSubmitted: (_) => _create(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 8 characters',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                    key: const Key('create-account'),
                    label: 'Create account',
                    busy: _busy,
                    onPressed: _busy ? null : _create,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
