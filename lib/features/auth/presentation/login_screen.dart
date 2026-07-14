import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';

/// Themed email-OTP login. Two steps: enter email → enter the 6-digit code
/// mailed back. Chrome is English only (D2). Persona output is not involved.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Step { email, code }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();

  _Step _step = _Step.email;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sendCode() => _run(() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty) {
      throw const FormatException('Enter your email to continue.');
    }
    await ref.read(authRepositoryProvider).sendOtp(email);
    if (mounted) {
      setState(() => _step = _Step.code);
    }
  });

  Future<void> _verify() => _run(() async {
    await ref
        .read(authRepositoryProvider)
        .verifyOtp(
          email: _emailController.text.trim(),
          token: _codeController.text.trim(),
        );
    // On success the session stream flips and the router redirects.
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Scaffold(
      backgroundColor: theme.colors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: theme.spacing.mobileMargin),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: theme.dimensions.maxReadableWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Center(child: PersonaOrb(isPulsing: true)),
                  SizedBox(height: theme.spacing.lg),
                  Text(
                    'Sidekick',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium,
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    _step == _Step.email
                        ? 'Sign in with your email.'
                        : 'Enter the 6-digit code we sent.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: theme.spacing.lg),
                  SurfaceCard(
                    child: _step == _Step.email
                        ? _emailStep(theme)
                        : _codeStep(theme),
                  ),
                  if (_error != null) ...<Widget>[
                    SizedBox(height: theme.spacing.md),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailStep(AppTheme theme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      SizedBox(height: theme.spacing.md),
      PillButton(
        label: _busy ? 'Sending…' : 'Send code',
        onPressed: _busy ? null : _sendCode,
      ),
    ],
  );

  Widget _codeStep(AppTheme theme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: '6-digit code'),
      ),
      SizedBox(height: theme.spacing.md),
      PillButton(
        label: _busy ? 'Verifying…' : 'Verify',
        onPressed: _busy ? null : _verify,
      ),
      SizedBox(height: theme.spacing.sm),
      PillButton(
        label: 'Use a different email',
        variant: PillButtonVariant.secondary,
        onPressed: _busy
            ? null
            : () => setState(() {
                _step = _Step.email;
                _error = null;
              }),
      ),
    ],
  );
}
