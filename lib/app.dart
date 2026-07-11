import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/router/app_router.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/theme_providers.dart';

class SidekickApp extends ConsumerWidget {
  const SidekickApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppTheme appTheme = ref.watch(activeThemeProvider);

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
