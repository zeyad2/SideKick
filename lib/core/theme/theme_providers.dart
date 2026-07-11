import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_theme_registry.dart';

final NotifierProvider<ActiveThemeName, String> activeThemeNameProvider =
    NotifierProvider<ActiveThemeName, String>(ActiveThemeName.new);

final Provider<AppTheme> activeThemeProvider = Provider<AppTheme>(
  (Ref ref) => AppThemeRegistry.byName(ref.watch(activeThemeNameProvider)),
);

final class ActiveThemeName extends Notifier<String> {
  @override
  String build() => AppThemeRegistry.defaultThemeName;

  void select(String name) {
    AppThemeRegistry.byName(name);
    state = name;
  }
}
