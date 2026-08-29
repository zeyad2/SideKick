import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/auth/auth_providers.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/router/app_router.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/theme_providers.dart';
import 'package:sidekick/features/capture/presentation/capture_overlay_host.dart';
import 'package:sidekick/features/inbox/application/inbox_providers.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler.dart';
import 'package:sidekick/features/reminders/application/reminder_scheduler_providers.dart';

class SidekickApp extends ConsumerStatefulWidget {
  const SidekickApp({super.key});

  @override
  ConsumerState<SidekickApp> createState() => _SidekickAppState();
}

class _SidekickAppState extends ConsumerState<SidekickApp> {
  late final AppLifecycleListener _lifecycle;
  ReminderScheduler? _attachedScheduler;

  @override
  void initState() {
    super.initState();
    // Flush + pull whenever the app returns to the foreground (best-effort).
    _lifecycle = AppLifecycleListener(
      onResume: () {
        ref.read(syncEngineProvider)?.syncNow();
        if (ref.read(currentUserIdProvider) != null) {
          final ReminderScheduler scheduler = ref.read(
            reminderSchedulerProvider,
          );
          _attachScheduler(scheduler, resync: true);
        }
      },
    );
    Future<void>.microtask(() {
      if (!mounted || ref.read(currentUserIdProvider) == null) return;
      final ReminderScheduler scheduler = ref.read(reminderSchedulerProvider);
      _attachScheduler(scheduler, resync: true);
    });
  }

  void _attachScheduler(ReminderScheduler scheduler, {required bool resync}) {
    if (identical(_attachedScheduler, scheduler)) {
      if (resync) unawaited(scheduler.resyncAll());
      return;
    }
    final ReminderScheduler? previous = _attachedScheduler;
    if (previous != null) {
      ReminderNotificationDispatcher.detach(previous);
    }
    _attachedScheduler = scheduler;
    ReminderNotificationDispatcher.attach(scheduler);
    if (resync) unawaited(scheduler.resyncAll());
  }

  void _detachScheduler() {
    final ReminderScheduler? scheduler = _attachedScheduler;
    if (scheduler == null) return;
    ReminderNotificationDispatcher.detach(scheduler);
    _attachedScheduler = null;
  }

  @override
  void dispose() {
    _detachScheduler();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme appTheme = ref.watch(activeThemeProvider);
    // Instantiate (and start) the sync engine for the signed-in user; it
    // reacts to connectivity regained on its own.
    ref.watch(syncEngineProvider);
    ref.watch(captureOwnerBindingProvider);
    ref.watch(audioReminderRetryControllerProvider);
    final bool signedIn = ref.watch(currentUserIdProvider) != null;
    if (signedIn) {
      final ReminderScheduler scheduler = ref.watch(reminderSchedulerProvider);
      if (!identical(_attachedScheduler, scheduler)) {
        _attachScheduler(scheduler, resync: true);
      }
    } else {
      _detachScheduler();
    }

    return AppThemeScope(
      theme: appTheme,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: ref.watch(appRouterProvider),
        theme: appTheme.toThemeData(),
        darkTheme: appTheme.toThemeData(),
        themeMode: ThemeMode.dark,
        builder: (BuildContext context, Widget? child) => Directionality(
          textDirection: TextDirection.ltr,
          child: CaptureOverlayHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
