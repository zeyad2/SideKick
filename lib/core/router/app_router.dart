import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/router/app_gate.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/features/auth/presentation/login_screen.dart';
import 'package:sidekick/features/focus/presentation/focus_screen.dart';
import 'package:sidekick/features/habits/presentation/habits_screen.dart';
import 'package:sidekick/features/inbox/presentation/inbox_screen.dart';
import 'package:sidekick/features/onboarding/presentation/onboarding_screen.dart';
import 'package:sidekick/features/settings/presentation/settings_screen.dart';
import 'package:sidekick/features/shell/presentation/app_shell.dart';
import 'package:sidekick/features/splash/presentation/splash_screen.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  // Re-evaluate the redirect whenever the single gate decision changes.
  final _RouterRefresh refresh = _RouterRefresh();
  ref.listen(appGateProvider, (_, _) => refresh.bump());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.inbox,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) {
      final AppGate gate = ref.read(appGateProvider);
      final String location = state.matchedLocation;
      switch (gate) {
        case AppGate.loading:
          return location == AppRoutes.splash ? null : AppRoutes.splash;
        case AppGate.login:
          return location == AppRoutes.login ? null : AppRoutes.login;
        case AppGate.onboarding:
          return location == AppRoutes.onboarding
              ? null
              : AppRoutes.onboarding;
        case AppGate.ready:
          return location == AppRoutes.login ||
                  location == AppRoutes.onboarding ||
                  location == AppRoutes.splash
              ? AppRoutes.inbox
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
                path: AppRoutes.inbox,
                name: AppRoutes.inboxName,
                builder: (_, _) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.habits,
                name: AppRoutes.habitsName,
                builder: (_, _) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.focus,
                name: AppRoutes.focusName,
                builder: (_, _) => const FocusScreen(),
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
