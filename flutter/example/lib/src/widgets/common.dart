import 'package:flutter/material.dart';

import '../theme.dart';

/// The dark background, with two soft colored lights behind the content.
class GlowBackground extends StatelessWidget {
  const GlowBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Palette.background)),
        const Positioned(
          top: -170,
          left: -130,
          child: _Light(color: Palette.indigo, size: 440),
        ),
        const Positioned(
          top: -70,
          right: -170,
          child: _Light(color: Palette.purple, size: 400),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Light extends StatelessWidget {
  const _Light({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}

/// The app's mark: a glowing fingerprint in a gradient circle.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: Palette.accent,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Palette.violet.withValues(alpha: 0.55),
              blurRadius: 50,
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Palette.indigo.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(Icons.fingerprint, color: Colors.white, size: size * 0.55),
      ),
    );
  }
}

/// The main action: white on the indigo to violet gradient, with a glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Its request is on its way: a spinner instead of the label.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled || busy ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: Palette.accent,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Palette.violet.withValues(alpha: 0.38),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: enabled ? onPressed : null,
              child: SizedBox(
                height: 58,
                child: Center(
                  child: busy
                      ? const ButtonSpinner(color: Colors.white)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                            ],
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
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

/// A softly lit card with a thin border.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Palette.border),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181822), Color(0xFF0F0F16)],
        ),
      ),
      child: child,
    );
  }
}

/// "or use your password", between two thin lines.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Palette.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              style: const TextStyle(color: Palette.muted, fontSize: 13.5),
            ),
          ),
          const Expanded(child: Divider(color: Palette.border)),
        ],
      ),
    );
  }
}

/// A short message at the bottom of the screen.
void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? Palette.danger : Palette.success,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// The small spinner inside a busy button.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 22,
    child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
  );
}
