import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/domain/enums.dart';
import 'package:sidekick/core/providers/repository_providers.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';
import 'package:sidekick/features/profile/domain/profile.dart';

/// First-run onboarding. Collects the persona response language (D2) and marks
/// onboarding complete. Chrome is English; this choice governs persona OUTPUT
/// only. Theme selection is deferred (only one theme exists).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  PersonaLanguage _selected = PersonaLanguage.english;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Ensure a local profile row exists so preferences have a home.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(profileRepositoryProvider).ensureExists();
    });
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    final ProfileRepository profiles = ref.read(profileRepositoryProvider);
    await profiles.setPersonaLanguage(_selected);
    await profiles.mergePrefs(<String, Object?>{
      Profile.onboardingCompletedKey: true,
    });
    // The router redirect reacts to the updated onboarding flag.
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: theme.spacing.mobileMargin,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: theme.dimensions.maxReadableWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: PersonaOrb()),
                  SizedBox(height: theme.spacing.lg),
                  Text(
                    'How should I talk to you?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    'This sets the language of my replies. '
                    'You can change it later in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: theme.spacing.lg),
                  _languageOption(
                    theme,
                    label: 'English',
                    value: PersonaLanguage.english,
                  ),
                  SizedBox(height: theme.spacing.md),
                  _languageOption(
                    theme,
                    label: 'Egyptian Arabic',
                    value: PersonaLanguage.egyptianArabic,
                  ),
                  SizedBox(height: theme.spacing.lg),
                  PillButton(
                    label: _busy ? 'Saving…' : 'Continue',
                    onPressed: _busy ? null : _finish,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageOption(
    AppTheme theme, {
    required String label,
    required PersonaLanguage value,
  }) {
    final bool selected = _selected == value;
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _selected = value),
      child: SurfaceCard(
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? theme.colors.primary
                  : theme.colors.onSurfaceVariant,
            ),
            SizedBox(width: theme.spacing.md),
            Text(label, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
