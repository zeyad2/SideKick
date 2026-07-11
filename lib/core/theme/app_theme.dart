import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_colors.dart';
import 'package:sidekick/core/theme/app_tokens.dart';

@immutable
final class AppTheme {
  AppTheme({
    required this.name,
    required this.colors,
    required this.textTheme,
    required this.spacing,
    required this.radii,
    required this.dimensions,
  }) : colorScheme = colors.toColorScheme();

  final String name;
  final AppColors colors;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final AppSpacing spacing;
  final AppRadii radii;
  final AppDimensions dimensions;

  AppTheme copyWith({String? name, AppColors? colors}) => AppTheme(
    name: name ?? this.name,
    colors: colors ?? this.colors,
    textTheme: textTheme,
    spacing: spacing,
    radii: radii,
    dimensions: dimensions,
  );

  ThemeData toThemeData() {
    final BorderRadius inputRadius = BorderRadius.circular(radii.input);
    final BorderRadius pillRadius = BorderRadius.circular(radii.pill);
    final BorderSide outlineSide = BorderSide(
      color: colors.outline,
      width: dimensions.outlineWidth,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      shadowColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      textTheme: textTheme,
      iconTheme: IconThemeData(
        color: colors.onSurfaceVariant,
        size: dimensions.navigationIcon,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainer,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.card),
          side: BorderSide(
            color: colors.cardBorder,
            width: dimensions.outlineWidth,
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radii.card),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        modalBackgroundColor: colors.surfaceContainerHigh,
        elevation: 0,
        modalElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
        shape: const CircleBorder(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: dimensions.navigationBarHeight,
        elevation: 0,
        backgroundColor: colors.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant,
            size: dimensions.navigationIcon,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: outlineSide.copyWith(color: colors.primary),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(dimensions.buttonMinHeight),
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          disabledBackgroundColor: colors.surfaceContainerHighest,
          disabledForegroundColor: colors.onSurfaceVariant,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: pillRadius),
          padding: EdgeInsets.symmetric(horizontal: spacing.card),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(dimensions.buttonMinHeight),
          foregroundColor: colors.onSurface,
          disabledForegroundColor: colors.onSurfaceVariant,
          side: outlineSide.copyWith(color: colors.onSurface),
          shape: RoundedRectangleBorder(borderRadius: pillRadius),
          padding: EdgeInsets.symmetric(horizontal: spacing.card),
          textStyle: textTheme.labelLarge,
        ),
      ),
    );
  }
}
