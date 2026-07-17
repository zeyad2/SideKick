import 'package:flutter/foundation.dart';

@immutable
final class AppSpacing {
  const AppSpacing({
    required this.unit,
    required this.xs,
    required this.sm,
    required this.md,
    required this.card,
    required this.lg,
    required this.xl,
    required this.gutter,
    required this.mobileMargin,
    required this.desktopMargin,
  });

  final double unit;
  final double xs;
  final double sm;
  final double md;
  final double card;
  final double lg;
  final double xl;
  final double gutter;
  final double mobileMargin;
  final double desktopMargin;
}

@immutable
final class AppRadii {
  const AppRadii({required this.card, required this.input, required this.pill});

  final double card;
  final double input;
  final double pill;
}

@immutable
final class AppDimensions {
  const AppDimensions({
    required this.outlineWidth,
    required this.personaOrb,
    required this.buttonMinHeight,
    required this.navigationIcon,
    required this.navigationBarHeight,
    required this.maxReadableWidth,
    required this.captureMic,
    required this.captureWaveformHeight,
    required this.captureOverlayBlur,
  });

  final double outlineWidth;
  final double personaOrb;
  final double buttonMinHeight;
  final double navigationIcon;
  final double navigationBarHeight;
  final double maxReadableWidth;
  final double captureMic;
  final double captureWaveformHeight;
  final double captureOverlayBlur;
}
