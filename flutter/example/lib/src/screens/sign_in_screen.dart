import 'package:flutter/material.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

import '../account_api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'sign_up_screen.dart';

/// Sign in with a passkey (no email, no password), or with a password.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _passwordBusy = false;
  bool _passkeyBusy = false;

  bool get _busy => _passwordBusy || _passkeyBusy;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signInWithPasskey() async {
    if (_busy) return;
    setState(() => _passkeyBusy = true);
    try {
      await AppScope.of(context).signInWithPasskey();
    } on PasskeyException catch (error) {
      // Closing the sheet isn't an error: show nothing.
      if (mounted && !error.isCancelled) {
        showMessage(context, error.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _passkeyBusy = false);
    }
  }

  Future<void> _signInWithPassword() async {
    if (_busy) return;
    setState(() => _passwordBusy = true);
    try {
      await AppScope.of(
        context,
      ).signIn(email: _email.text.trim(), password: _password.text);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _passwordBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);

    return Scaffold(
      body: GlowBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandMark(),
                      const SizedBox(height: 34),
                      Text(
                        'Welcome back',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in with Face ID or your fingerprint.\n'
                        'No password to remember.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Palette.muted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 36),
                      // Only on a phone that can use passkeys.
                      FutureBuilder<bool>(
                        future: state.passkeys.isAvailable(),
                        builder: (context, snapshot) {
                          if (snapshot.data != true) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GradientButton(
                                key: const Key('passkey-sign-in'),
                                icon: Icons.fingerprint,
                                label: 'Sign in with a passkey',
                                busy: _passkeyBusy,
                                onPressed: _busy ? null : _signInWithPasskey,
                              ),
                              const OrDivider(label: 'or use your password'),
                            ],
                          );
                        },
                      ),
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
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _signInWithPassword(),
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton(
                        key: const Key('password-sign-in'),
                        onPressed: _busy ? null : _signInWithPassword,
                        child: _passwordBusy
                            ? const ButtonSpinner()
                            : const Text('Sign in with password'),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const SignUpScreen(),
                                ),
                              ),
                        child: const Text.rich(
                          TextSpan(
                            text: 'New here?  ',
                            style: TextStyle(color: Palette.muted),
                            children: [
                              TextSpan(
                                text: 'Create an account',
                                style: TextStyle(
                                  color: Palette.link,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
