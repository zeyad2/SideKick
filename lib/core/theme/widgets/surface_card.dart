import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colors.surfaceContainer,
        border: Border.all(
          color: theme.colors.cardBorder,
          width: theme.dimensions.outlineWidth,
        ),
        borderRadius: BorderRadius.circular(theme.radii.card),
      ),
      child: Padding(padding: EdgeInsets.all(theme.spacing.card), child: child),
    );
  }
}
