import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';

/// Shown to a signed-in user while the gate waits for the first sync to settle,
/// so a returning user on a fresh install is never flashed the onboarding flow.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: const Center(child: PersonaOrb(isPulsing: true)),
    );
  }
}
