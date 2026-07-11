import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme.dart';

class AppThemeScope extends InheritedWidget {
  const AppThemeScope({required this.theme, required super.child, super.key});

  final AppTheme theme;

  static AppTheme of(BuildContext context) {
    final AppThemeScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null, 'No AppThemeScope found in this context.');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) => theme != oldWidget.theme;
}

extension AppThemeContext on BuildContext {
  AppTheme get appTheme => AppThemeScope.of(this);
}
