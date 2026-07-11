import 'package:sidekick/core/theme/analog_companion_theme.dart';
import 'package:sidekick/core/theme/app_theme.dart';

final class AppThemeRegistry {
  AppThemeRegistry._();

  static const String defaultThemeName = 'analog_companion';

  static final Map<String, AppTheme> themes =
      Map<String, AppTheme>.unmodifiable(<String, AppTheme>{
        defaultThemeName: buildAnalogCompanionTheme(),
      });

  static AppTheme byName(String name) {
    final AppTheme? theme = themes[name];
    if (theme == null) {
      throw ArgumentError.value(name, 'name', 'Unknown app theme');
    }
    return theme;
  }
}
