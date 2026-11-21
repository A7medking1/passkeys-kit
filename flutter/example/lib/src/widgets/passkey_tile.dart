import 'package:flutter/material.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

import '../formatting.dart';
import '../theme.dart';
import 'common.dart';

/// One passkey: the device it was made on, when, when it last signed the
/// user in, and its delete button.
class PasskeyTile extends StatelessWidget {
  const PasskeyTile({
    super.key,
    required this.passkey,
    required this.onDelete,
    this.busy = false,
  });

  final PasskeyInfo passkey;
  final VoidCallback onDelete;

  /// Its delete request is on its way.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: Palette.muted,
      fontSize: 13,
    );
    final createdAt = passkey.createdAt;
    final lastUsedAt = passkey.lastUsedAt;

    return GlassCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: Palette.accent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Palette.violet.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.fingerprint, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        passkey.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (passkey.isSynced) ...[
                      const SizedBox(width: 8),
                      const _SyncedPill(),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                if (createdAt != null)
                  Text('Added ${formatDate(createdAt)}', style: muted),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: lastUsedAt == null
                            ? Palette.muted.withValues(alpha: 0.6)
                            : Palette.success,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      lastUsedAt == null
                          ? 'Not used yet'
                          : 'Last used ${timeAgo(lastUsedAt)}',
                      style: muted,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox.square(
              dimension: 48,
              child: Center(child: ButtonSpinner()),
            )
          else
            IconButton(
              key: ValueKey('delete-${passkey.id}'),
              tooltip: 'Delete passkey',
              onPressed: onDelete,
              style: IconButton.styleFrom(
                backgroundColor: Palette.danger.withValues(alpha: 0.10),
                foregroundColor: Palette.danger,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 21),
            ),
        ],
      ),
    );
  }
}

/// "Synced": it lives in iCloud Keychain or Google Password Manager.
class _SyncedPill extends StatelessWidget {
  const _SyncedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Palette.success.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_done_rounded, size: 13, color: Palette.success),
          SizedBox(width: 4),
          Text(
            'Synced',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Palette.success,
            ),
          ),
        ],
      ),
    );
  }
}
