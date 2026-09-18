import 'package:flutter/material.dart';

/// Big rounded tappable button used everywhere in blind mode.
///
/// Minimum height 68 dp for comfortable touch targets, but it is a MINIMUM and
/// not a fixed size: the label wraps and the button grows.
///
/// It used to sit in a fixed 68 dp box with `TextOverflow.ellipsis`, so at the
/// larger text sizes this app exists to provide, the label was silently cut
/// off ("Speak, check the simplifie…") instead of wrapping. A blind user's
/// button label must never be truncated.
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
      enabled: onPressed != null,
      // A screen reader announces this ONE string. Without excludeSemantics the
      // icon and both lines were read separately, repeating the label.
      label: subtext == null ? label : '$label. $subtext',
      excludeSemantics: true,
      // CRITICAL: excludeSemantics drops the button's own semantics, so its
      // tap action has to be re-published here or a screen-reader user can no
      // longer activate the control at all.
      onTap: onPressed,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            minimumSize: const Size.fromHeight(68),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // No ellipsis and no maxLines: a blind user's label must never be
              // cut off. The button grows instead.
              Text(label),
              if (subtext != null)
                Text(
                  subtext!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: fg.withValues(alpha: 0.85),
                  ),
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

/// Labelled slider with a live value read-out.
///
/// Shared by the messaging settings and the sign-tool settings. Both screens
/// used to carry their own private copy, which is how they drifted apart.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: valueLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label)),
              Text(valueLabel),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: valueLabel,
            onChanged: onChanged,
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
