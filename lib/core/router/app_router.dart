import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sidekick/core/router/app_routes.dart';
import 'package:sidekick/features/focus/presentation/focus_screen.dart';
import 'package:sidekick/features/habits/presentation/habits_screen.dart';
import 'package:sidekick/features/inbox/presentation/inbox_screen.dart';
import 'package:sidekick/features/settings/presentation/settings_screen.dart';
import 'package:sidekick/features/shell/presentation/app_shell.dart';

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>(
  (Ref ref) => GoRouter(
    initialLocation: AppRoutes.inbox,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.inbox,
                name: AppRoutes.inboxName,
                builder: (context, state) => const InboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.habits,
                name: AppRoutes.habitsName,
                builder: (context, state) => const HabitsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.focus,
                name: AppRoutes.focusName,
                builder: (context, state) => const FocusScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: AppRoutes.settings,
                name: AppRoutes.settingsName,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  ),
);
