import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/router/app_router.dart';
import 'package:sidekick/core/sync/sync_providers.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/theme_providers.dart';

class SidekickApp extends ConsumerStatefulWidget {
  const SidekickApp({super.key});

  @override
  ConsumerState<SidekickApp> createState() => _SidekickAppState();
}

class _SidekickAppState extends ConsumerState<SidekickApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Flush + pull whenever the app returns to the foreground (best-effort).
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(syncEngineProvider)?.syncNow(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTheme appTheme = ref.watch(activeThemeProvider);
    // Instantiate (and start) the sync engine for the signed-in user; it
    // reacts to connectivity regained on its own.
    ref.watch(syncEngineProvider);

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
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
