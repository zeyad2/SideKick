import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/auth/auth_repository.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';
import 'package:sidekick/core/theme/widgets/surface_card.dart';

/// Themed email + password auth. One screen with a sign-in / create-account
/// toggle — no email verification (deliberate low-friction onboarding, D2).
/// Google sign-in is designed in but disabled until the native setup lands.
/// Chrome is English only. Persona output is not involved.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { signIn, signUp }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  // Supabase's default minimum password length.
  static const int _minPasswordLength = 6;
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    // Cheap client-side validation so a typo doesn't round-trip to Supabase.
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < _minPasswordLength) {
      setState(
        () => _error =
            'Password must be at least $_minPasswordLength characters.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final AuthRepository auth = ref.read(authRepositoryProvider);
      switch (_mode) {
        case _Mode.signIn:
          await auth.signInWithPassword(email: email, password: password);
        case _Mode.signUp:
          await auth.signUpWithPassword(email: email, password: password);
      }
      // On success the session stream flips and the router redirects.
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

  /// Map the common Supabase auth failures to human copy; fall back to the raw
  /// message so nothing is silently swallowed.
  String _friendlyError(Object error) {
    final String raw = error.toString().toLowerCase();
    if (raw.contains('invalid login credentials')) {
      return 'Wrong email or password.';
    }
    if (raw.contains('already registered') ||
        raw.contains('user already exists')) {
      return 'That email already has an account. Try signing in.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host')) {
      return 'No connection. Check your network and try again.';
    }
    return error.toString().replaceFirst('AuthException: ', '');
  }

  void _toggleMode() {
    setState(() {
      _mode = _mode == _Mode.signIn ? _Mode.signUp : _Mode.signIn;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final bool isSignUp = _mode == _Mode.signUp;
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
                    'Sidekick',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displayMedium,
                  ),
                  SizedBox(height: theme.spacing.sm),
                  Text(
                    isSignUp
                        ? 'Create your account to get started.'
                        : 'Welcome back.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colors.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: theme.spacing.lg),
                  SurfaceCard(child: _form(theme, isSignUp: isSignUp)),
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
                  _dividerOr(theme),
                  SizedBox(height: theme.spacing.lg),
                  _googleButton(theme),
                  SizedBox(height: theme.spacing.lg),
                  _modeToggle(theme, isSignUp: isSignUp),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(AppTheme theme, {required bool isSignUp}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      SizedBox(height: theme.spacing.md),
      TextField(
        controller: _passwordController,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !_busy,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _busy ? null : _submit(),
        decoration: InputDecoration(
          labelText: 'Password',
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _obscure = !_obscure),
            tooltip: _obscure ? 'Show password' : 'Hide password',
          ),
        ),
      ),
      SizedBox(height: theme.spacing.md),
      PillButton(
        label: _busy
            ? (isSignUp ? 'Creating…' : 'Signing in…')
            : (isSignUp ? 'Create account' : 'Sign in'),
        onPressed: _busy ? null : _submit,
      ),
      if (!isSignUp)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy
                ? null
                : () => context.goNamed(AppRoutes.forgotPasswordName),
            child: const Text('Forgot password?'),
          ),
        ),
    ],
  );

  Widget _dividerOr(AppTheme theme) => Row(
    children: <Widget>[
      Expanded(child: Divider(color: theme.colors.outline)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: theme.spacing.md),
        child: Text(
          'or',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colors.onSurfaceVariant,
          ),
        ),
      ),
      Expanded(child: Divider(color: theme.colors.outline)),
    ],
  );

  /// Google sign-in, designed in but disabled until the native `google_sign_in`
  /// + Google Cloud console setup lands (see techdebt.md). `onPressed: null`
  /// gives it the built-in disabled styling; the trailing chip says why.
  Widget _googleButton(AppTheme theme) => OutlinedButton(
    onPressed: null,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Icon(Icons.g_mobiledata, size: 28),
        SizedBox(width: theme.spacing.sm),
        const Text('Continue with Google'),
        SizedBox(width: theme.spacing.sm),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: theme.spacing.sm,
            vertical: theme.spacing.xs,
          ),
          decoration: BoxDecoration(
            color: theme.colors.surfaceVariant,
            borderRadius: BorderRadius.circular(theme.radii.input),
          ),
          child: Text(
            'Soon',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _modeToggle(AppTheme theme, {required bool isSignUp}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Text(
        isSignUp ? 'Already have an account?' : 'New to Sidekick?',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colors.onSurfaceVariant,
        ),
      ),
      TextButton(
        onPressed: _busy ? null : _toggleMode,
        child: Text(isSignUp ? 'Sign in' : 'Create account'),
      ),
    ],
  );
}
