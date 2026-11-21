import 'package:flutter/material.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/passkey_tile.dart';

/// Signed in: the account, its passkeys, and adding one on this phone.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<PasskeyInfo>? _passkeys;
  String? _error;
  bool _adding = false;
  String? _deletingId;

  PasskeyClient get _client => AppScope.of(context).passkeys;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_passkeys == null && _error == null) _load();
  }

  Future<void> _load() async {
    try {
      final passkeys = await _client.list();
      if (mounted) {
        setState(() {
          _passkeys = passkeys;
          _error = null;
        });
      }
    } on PasskeyException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await _client.register();
      await _load();
      if (mounted) {
        showMessage(context, 'Passkey added. Use it to sign in next time.');
      }
    } on PasskeyException catch (error) {
      if (mounted && !error.isCancelled) {
        showMessage(context, error.message, error: true);
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(PasskeyInfo passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this passkey?'),
        content: const Text(
          "You won't be able to sign in with it any more. It stays in your "
          "phone's password manager until you delete it there too.",
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.danger,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingId = passkey.id);
    try {
      await _client.delete(passkey.id);
      await _load();
    } on PasskeyException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final passkeys = _passkeys;

    return Scaffold(
      extendBody: true,
      body: GlowBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _load,
            color: Palette.violet,
            backgroundColor: Palette.surfaceHigh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
              children: [
                _TopBar(onSignOut: state.signOut),
                const SizedBox(height: 20),
                _ProfileCard(account: state.account!, method: state.method),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Text('Your passkeys', style: theme.textTheme.titleLarge),
                    if (passkeys != null && passkeys.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _CountBadge(count: passkeys.length),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Sign in with Face ID or your fingerprint. A passkey never '
                  "leaves your password manager, and it can't be phished.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Palette.muted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                if (_error != null && passkeys == null)
                  _ErrorCard(message: _error!, onRetry: _load)
                else if (passkeys == null)
                  const Padding(
                    padding: EdgeInsets.all(36),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (passkeys.isEmpty)
                  const _NoPasskeys()
                else
                  for (final passkey in passkeys) ...[
                    PasskeyTile(
                      key: ValueKey(passkey.id),
                      passkey: passkey,
                      busy: _deletingId == passkey.id,
                      onDelete: () => _delete(passkey),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FutureBuilder<bool>(
        future: _client.isAvailable(),
        builder: (context, snapshot) {
          final available = snapshot.data;
          if (available == null) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Palette.background.withValues(alpha: 0),
                  Palette.background,
                ],
                stops: const [0, 0.45],
              ),
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 16),
              child: available
                  ? GradientButton(
                      key: const Key('add-passkey'),
                      icon: Icons.add_rounded,
                      label: 'Add a passkey',
                      busy: _adding,
                      onPressed: _adding ? null : _add,
                    )
                  : Text(
                      "This phone can't use passkeys. They need iOS 16 or "
                      'Android 9 with a screen lock.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Palette.muted,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: Palette.accent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.fingerprint, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        Text(
          'Passkeys Kit',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Sign out',
          onPressed: onSignOut,
          style: IconButton.styleFrom(
            backgroundColor: Palette.surface,
            foregroundColor: Palette.muted,
            side: const BorderSide(color: Palette.border),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.account, required this.method});

  final Account account;
  final SignInMethod? method;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = account.name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final withPasskey = method == SignInMethod.passkey;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Palette.accent,
              boxShadow: [
                BoxShadow(
                  color: Palette.violet.withValues(alpha: 0.4),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: theme.textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  account.email,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Palette.muted,
                  ),
                ),
                const SizedBox(height: 10),
                _Chip(
                  icon: withPasskey
                      ? Icons.fingerprint
                      : Icons.lock_outline_rounded,
                  label: withPasskey
                      ? 'Signed in with a passkey'
                      : 'Signed in with your password',
                  color: withPasskey ? Palette.success : Palette.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.violet.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Palette.link,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _NoPasskeys extends StatelessWidget {
  const _NoPasskeys();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: Palette.accent,
              boxShadow: [
                BoxShadow(
                  color: Palette.violet.withValues(alpha: 0.45),
                  blurRadius: 34,
                ),
              ],
            ),
            child: const Icon(Icons.key_rounded, size: 32, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            'No passkeys yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add one, and sign in with Face ID next time.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
