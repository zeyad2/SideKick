import 'package:flutter/material.dart';

enum PillButtonVariant { primary, secondary }

class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.variant = PillButtonVariant.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final PillButtonVariant variant;

  @override
  Widget build(BuildContext context) => switch (variant) {
    PillButtonVariant.primary => FilledButton(
      onPressed: onPressed,
      child: Text(label),
    ),
    PillButtonVariant.secondary => OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    ),
  };
}
