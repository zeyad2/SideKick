import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';

class PersonaOrb extends StatelessWidget {
  const PersonaOrb({this.isPulsing = false, super.key});

  final bool isPulsing;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return Semantics(
      label: isPulsing ? 'Companion active' : 'Companion',
      child: SizedBox.square(
        dimension: theme.dimensions.personaOrb,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colors.primaryContainer,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
