import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/features/auth/presentation/login_screen.dart';
import 'package:sidekick/features/focus/presentation/focus_screen.dart';
import 'package:sidekick/features/habits/presentation/habits_screen.dart';
import 'package:sidekick/features/inbox/presentation/inbox_screen.dart';
import 'package:sidekick/features/onboarding/presentation/onboarding_screen.dart';
import 'package:sidekick/features/profile/preferences_providers.dart';
import 'package:sidekick/features/settings/presentation/settings_screen.dart';
import 'package:sidekick/features/shell/presentation/app_shell.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((Ref ref) {
  // Refresh the router whenever auth or onboarding state changes.
  final _RouterRefresh refresh = _RouterRefresh();
  ref.listen(sessionProvider, (_, _) => refresh.bump());
  ref.listen(onboardingCompletedProvider, (_, _) => refresh.bump());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: AppRoutes.inbox,
    refreshListenable: refresh,
    redirect: (_, GoRouterState state) {
      // `current` reads the CACHED session synchronously — no network wait.
      final bool signedIn = ref.read(authRepositoryProvider).current.isSignedIn;
      final bool onboarded = ref.read(onboardingCompletedProvider);
      final String location = state.matchedLocation;

      if (!signedIn) {
        return location == AppRoutes.login ? null : AppRoutes.login;
      }
      if (!onboarded) {
        return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
      }
      if (location == AppRoutes.login || location == AppRoutes.onboarding) {
        return AppRoutes.inbox;
      }
      return null;
    },
    routes: <RouteBase>[
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
