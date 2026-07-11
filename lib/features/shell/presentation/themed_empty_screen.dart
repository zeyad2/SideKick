import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';

class ThemedEmptyScreen extends StatelessWidget {
  const ThemedEmptyScreen({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: theme.dimensions.maxReadableWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.mobileMargin,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium,
                ),
                SizedBox(height: theme.spacing.lg),
                const PersonaOrb(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
