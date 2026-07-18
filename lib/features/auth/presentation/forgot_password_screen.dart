import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';

/// Request a password-reset email. Reached from the sign-in form while signed
/// out. Sending the email is fully wired; completing the reset (following the
/// emailed link back into the app to set a new password) needs deep-link
/// handling that is not built yet — see techdebt.md.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();

  bool _busy = false;
  bool _sent = false;
  String? _error;

  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email: email);
      if (mounted) {
        setState(() => _sent = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _friendlyError(Object error) {
    final String raw = error.toString().toLowerCase();
    if (raw.contains('socketexception') || raw.contains('failed host')) {
      return 'No connection. Check your network and try again.';
    }
    return error.toString().replaceFirst('AuthException: ', '');
  }

  void _backToSignIn() => context.goNamed(AppRoutes.loginName);

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
                  const Center(child: PersonaOrb(isPulsing: true)),
                  SizedBox(height: theme.spacing.lg),
                  Text(
                    'Reset password',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium,
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    _sent
                        ? 'If that email has an account, a reset link is on its '
                              'way. Check your inbox.'
                        : 'Enter your email and we\'ll send you a reset link.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: theme.spacing.lg),
                  if (!_sent) SurfaceCard(child: _form(theme)),
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
                  SizedBox(height: theme.spacing.lg),
                  TextButton(
                    onPressed: _busy ? null : _backToSignIn,
                    child: const Text('Back to sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(AppTheme theme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        autocorrect: false,
        enabled: !_busy,
        onSubmitted: (_) => _busy ? null : _submit(),
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      SizedBox(height: theme.spacing.md),
      PillButton(
        label: _busy ? 'Sending…' : 'Send reset link',
        onPressed: _busy ? null : _submit,
      ),
    ],
  );
}
