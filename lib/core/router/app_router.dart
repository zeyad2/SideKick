import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/router/app_gate.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/features/auth/presentation/forgot_password_screen.dart';
import 'package:sidekick/features/auth/presentation/login_screen.dart';
import 'package:sidekick/features/inbox/presentation/inbox_screen.dart';
import 'package:sidekick/features/onboarding/presentation/onboarding_screen.dart';
import 'package:sidekick/features/settings/presentation/settings_screen.dart';
import 'package:sidekick/features/shell/presentation/app_shell.dart';
import 'package:sidekick/features/shell/presentation/themed_empty_screen.dart';
import 'package:sidekick/features/splash/presentation/splash_screen.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  // Re-evaluate the redirect whenever the single gate decision changes.
  final _RouterRefresh refresh = _RouterRefresh();
  ref.listen(appGateProvider, (_, _) => refresh.bump());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.capture,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) {
      final AppGate gate = ref.read(appGateProvider);
      final String location = state.matchedLocation;
      switch (gate) {
        case AppGate.loading:
          return location == AppRoutes.splash ? null : AppRoutes.splash;
        case AppGate.login:
          return location == AppRoutes.login ||
                  location == AppRoutes.forgotPassword
              ? null
              : AppRoutes.login;
        case AppGate.onboarding:
          return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
        case AppGate.ready:
          return location == AppRoutes.login ||
                  location == AppRoutes.forgotPassword ||
                  location == AppRoutes.onboarding ||
                  location == AppRoutes.splash
              ? AppRoutes.capture
              : null;
      }
    },
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (_, _) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: AppRoutes.loginName,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: AppRoutes.forgotPasswordName,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboardingName,
        builder: (_, _) => const OnboardingScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, StatefulNavigationShell navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.capture,
                name: AppRoutes.captureName,
                builder: (_, GoRouterState state) => InboxScreen(
                  editReminderId: state.uri.queryParameters['editReminderId'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.reminders,
                name: AppRoutes.remindersName,
                builder: (_, _) =>
                    const ThemedEmptyScreen(title: 'Task reminders'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.places,
                name: AppRoutes.placesName,
                builder: (_, _) => const ThemedEmptyScreen(title: 'Places'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                name: AppRoutes.settingsName,
                builder: (_, _) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// A minimal [Listenable] that go_router re-evaluates its redirect on.
class _RouterRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}
