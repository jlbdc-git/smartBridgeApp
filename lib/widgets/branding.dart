import 'package:flutter/material.dart';

/// SmartBridge app logo (extracted unchanged from the original main.dart).
class SmartBridgeLogo extends StatelessWidget {
  const SmartBridgeLogo({
    super.key,
    this.size = 38,
    this.backgroundColor,
    this.borderColor,
  });

  final double size;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: backgroundColor ?? scheme.primaryContainer,
        border: Border.all(
          color: borderColor ?? scheme.primary.withValues(alpha: 0.45),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.18),
        child: Image.asset(
          'smartbridge.png',
          fit: BoxFit.cover,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return Icon(
                  Icons.sign_language,
                  size: size * 0.5,
                  color: scheme.primary,
                );
              },
        ),
      ),
    );
  }
}
