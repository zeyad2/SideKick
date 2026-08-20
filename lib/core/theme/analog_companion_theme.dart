import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_colors.dart';
import 'package:sidekick/core/theme/app_theme.dart';
import 'package:sidekick/core/theme/app_tokens.dart';

const String _displayFont = 'DM Serif Display';
const String _bodyFont = 'DM Sans';

AppTheme buildAnalogCompanionTheme() {
  const AppColors colors = AppColors(
    surface: Color(0xFF161311),
    surfaceDim: Color(0xFF161311),
    surfaceBright: Color(0xFF3C3836),
    surfaceContainerLowest: Color(0xFF100E0C),
    surfaceContainerLow: Color(0xFF1E1B19),
    surfaceContainer: Color(0xFF221F1D),
    surfaceContainerHigh: Color(0xFF2D2927),
    surfaceContainerHighest: Color(0xFF383432),
    onSurface: Color(0xFFE9E1DD),
    onSurfaceVariant: Color(0xFFD8C3AF),
    inverseSurface: Color(0xFFE9E1DD),
    inverseOnSurface: Color(0xFF33302D),
    outline: Color(0xFFA08E7B),
    outlineVariant: Color(0xFF534435),
    surfaceTint: Color(0xFFFFB963),
    primary: Color(0xFFFFB963),
    onPrimary: Color(0xFF472A00),
    primaryContainer: Color(0xFFD4860A),
    onPrimaryContainer: Color(0xFF472900),
    inversePrimary: Color(0xFF875300),
    secondary: Color(0xFF5BDBC1),
    onSecondary: Color(0xFF00382E),
    secondaryContainer: Color(0xFF00A68E),
    onSecondaryContainer: Color(0xFF00332A),
    tertiary: Color(0xFF9ACBFF),
    onTertiary: Color(0xFF003355),
    tertiaryContainer: Color(0xFF679BD0),
    onTertiaryContainer: Color(0xFF003154),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    primaryFixed: Color(0xFFFFDDB9),
    primaryFixedDim: Color(0xFFFFB963),
    onPrimaryFixed: Color(0xFF2B1700),
    onPrimaryFixedVariant: Color(0xFF663E00),
    secondaryFixed: Color(0xFF7AF8DC),
    secondaryFixedDim: Color(0xFF5BDBC1),
    onSecondaryFixed: Color(0xFF00201A),
    onSecondaryFixedVariant: Color(0xFF005144),
    tertiaryFixed: Color(0xFFD0E4FF),
    tertiaryFixedDim: Color(0xFF9ACBFF),
    onTertiaryFixed: Color(0xFF001D34),
    onTertiaryFixedVariant: Color(0xFF004A79),
    background: Color(0xFF161311),
    onBackground: Color(0xFFE9E1DD),
    surfaceVariant: Color(0xFF383432),
    cardBorder: Color(0x0FFFFFFF),
    // secondaryContainer at 16% and secondary at 40% — the Fresh Start chip.
    secondarySurface: Color(0x2900A68E),
    secondaryOutline: Color(0x665BDBC1),
  );

  final TextTheme textTheme = TextTheme(
    displayLarge: _serifStyle(size: 48, height: 1.1, color: colors.onSurface),
    displayMedium: _serifStyle(size: 32, height: 1.2, color: colors.onSurface),
    displaySmall: _serifStyle(size: 32, height: 1.2, color: colors.onSurface),
    headlineLarge: _serifStyle(size: 32, height: 1.2, color: colors.onSurface),
    headlineMedium: _serifStyle(size: 24, height: 1.3, color: colors.onSurface),
    headlineSmall: _serifStyle(size: 24, height: 1.3, color: colors.onSurface),
    titleLarge: _sansStyle(
      size: 18,
      height: 1.4,
      weight: FontWeight.w500,
      color: colors.onSurface,
    ),
    titleMedium: _sansStyle(
      size: 16,
      height: 1.4,
      weight: FontWeight.w500,
      color: colors.onSurface,
    ),
    titleSmall: _sansStyle(
      size: 14,
      height: 1.4,
      weight: FontWeight.w500,
      color: colors.onSurface,
    ),
    bodyLarge: _sansStyle(size: 18, height: 1.6, color: colors.onSurface),
    bodyMedium: _sansStyle(size: 16, height: 1.5, color: colors.onSurface),
    bodySmall: _sansStyle(
      size: 14,
      height: 1.4,
      color: colors.onSurfaceVariant,
    ),
    labelLarge: _sansStyle(
      size: 14,
      height: 1.4,
      weight: FontWeight.w500,
      letterSpacing: 0.7,
      color: colors.onSurface,
    ),
    labelMedium: _sansStyle(
      size: 12,
      height: 1.4,
      weight: FontWeight.w500,
      letterSpacing: 0.24,
      color: colors.onSurface,
    ),
    labelSmall: _sansStyle(
      size: 12,
      height: 1.4,
      weight: FontWeight.w500,
      letterSpacing: 0.24,
      color: colors.onSurfaceVariant,
    ),
  );

  return AppTheme(
    name: 'Analog Companion',
    colors: colors,
    textTheme: textTheme,
    spacing: const AppSpacing(
      unit: 4,
      xs: 4,
      sm: 8,
      md: 16,
      card: 20,
      lg: 24,
      xl: 32,
      gutter: 16,
      mobileMargin: 20,
      desktopMargin: 40,
    ),
    radii: const AppRadii(card: 12, input: 8, pill: 999),
    dimensions: const AppDimensions(
      outlineWidth: 1,
      personaOrb: 44,
      buttonMinHeight: 48,
      navigationIcon: 24,
      navigationBarHeight: 80,
      maxReadableWidth: 720,
      captureMic: 80,
      captureWaveformHeight: 72,
      captureOverlayBlur: 16,
    ),
  );
}

TextStyle _serifStyle({
  required double size,
  required double height,
  required Color color,
}) => TextStyle(
  fontFamily: _displayFont,
  fontSize: size,
  fontWeight: FontWeight.w400,
  fontStyle: FontStyle.italic,
  height: height,
  color: color,
);

TextStyle _sansStyle({
  required double size,
  required double height,
  required Color color,
  FontWeight weight = FontWeight.w400,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: _bodyFont,
  fontSize: size,
  fontWeight: weight,
  height: height,
  letterSpacing: letterSpacing,
  color: color,
);
