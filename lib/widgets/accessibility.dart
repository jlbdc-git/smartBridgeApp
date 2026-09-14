import 'package:flutter/material.dart';

/// Big rounded tappable button used everywhere in blind mode.
/// Minimum height 64 dp for comfortable touch targets.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.subtext,
    this.color,
    this.onColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? subtext;
  final Color? color;
  final Color? onColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg = color ?? scheme.primary;
    final Color fg = onColor ?? scheme.onPrimary;

    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: double.infinity,
        height: 68,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          icon: Icon(icon, size: 28),
          label: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, overflow: TextOverflow.ellipsis),
              if (subtext != null)
                Text(
                  subtext!,
                  style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.85)),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable status banner: offline notice, permission errors, etc.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    required this.icon,
    this.color,
    this.action,
  });

  final String message;
  final IconData icon;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg = (color ?? scheme.error).withValues(alpha: 0.14);
    final Color fg = color ?? scheme.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Card wrapper for translation previews.
class PreviewCard extends StatelessWidget {
  const PreviewCard({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
  });

  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

/// Friendly empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
