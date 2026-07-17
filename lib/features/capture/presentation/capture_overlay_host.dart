import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/core/capture/capture_coordinator.dart';
import 'package:sidekick/core/capture/capture_providers.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';
import 'package:sidekick/core/theme/widgets/persona_orb.dart';
import 'package:sidekick/core/theme/widgets/pill_button.dart';

class CaptureOverlayHost extends ConsumerWidget {
  const CaptureOverlayHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CaptureCoordinator? coordinator = ref.watch(
      captureCoordinatorProvider,
    );
    if (coordinator == null) return child;
    return StreamBuilder<CaptureOverlayState>(
      stream: coordinator.states,
      initialData: coordinator.currentState,
      builder: (BuildContext context, AsyncSnapshot<CaptureOverlayState> snap) {
        final CaptureOverlayState state =
            snap.data ?? const CaptureOverlayState();
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child,
            if (state.stage != CaptureOverlayStage.hidden)
              _CaptureBackdrop(
                child: switch (state.stage) {
                  CaptureOverlayStage.recording => _RecordingOverlay(
                    state: state,
                    onDone: coordinator.stopCapture,
                  ),
                  CaptureOverlayStage.processing => _ProcessingOverlay(
                    step: state.processingStep,
                  ),
                  CaptureOverlayStage.failed => _CaptureErrorOverlay(
                    code: state.errorCode,
                    onDismiss: coordinator.dismissError,
                  ),
                  CaptureOverlayStage.hidden => const SizedBox.shrink(),
                },
              ),
          ],
        );
      },
    );
  }
}

class _CaptureBackdrop extends StatelessWidget {
  const _CaptureBackdrop({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Material(
      color: theme.colors.background.withValues(alpha: 0.86),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: theme.dimensions.captureOverlayBlur,
          sigmaY: theme.dimensions.captureOverlayBlur,
        ),
        child: SafeArea(child: child),
      ),
    );
  }
}

class _RecordingOverlay extends StatefulWidget {
  const _RecordingOverlay({required this.state, required this.onDone});
  final CaptureOverlayState state;
  final Future<void> Function() onDone;

  @override
  State<_RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<_RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final Duration elapsed = DateTime.now().difference(
      widget.state.startedAt ?? DateTime.now(),
    );
    final String timer =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: EdgeInsets.all(theme.spacing.mobileMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text('I’m listening.', style: theme.textTheme.headlineLarge),
          SizedBox(height: theme.spacing.xl),
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) => Transform.scale(
              scale: MediaQuery.disableAnimationsOf(context)
                  ? 1
                  : 1 + (_pulse.value * 0.1),
              child: child,
            ),
            child: Container(
              width: theme.dimensions.captureMic,
              height: theme.dimensions.captureMic,
              decoration: BoxDecoration(
                color: theme.colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.mic_rounded,
                color: theme.colors.onPrimaryContainer,
                size: theme.dimensions.captureMic / 2,
              ),
            ),
          ),
          SizedBox(height: theme.spacing.xl),
          SizedBox(
            height: theme.dimensions.captureWaveformHeight,
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                color: theme.colors.primary,
                amplitude: widget.state.amplitude,
              ),
            ),
          ),
          SizedBox(height: theme.spacing.lg),
          Text(timer, style: theme.textTheme.titleLarge),
          SizedBox(height: theme.spacing.xl),
          PillButton(label: 'Done', onPressed: widget.onDone),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.color, required this.amplitude});
  final Color color;
  final int amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    const int bars = 24;
    final double normalized = math.max(0.08, amplitude / 32767).clamp(0, 1);
    final double slot = size.width / bars;
    final Paint paint = Paint()..color = color;
    for (var index = 0; index < bars; index += 1) {
      final double wave = 0.3 + 0.7 * math.sin((index + 1) * 1.7).abs();
      final double height = size.height * normalized * wave;
      final Rect bar = Rect.fromCenter(
        center: Offset(slot * (index + 0.5), size.height / 2),
        width: slot * 0.45,
        height: math.max(size.height * 0.08, height),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bar, Radius.circular(slot)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      amplitude != oldDelegate.amplitude || color != oldDelegate.color;
}

class _ProcessingOverlay extends StatelessWidget {
  const _ProcessingOverlay({required this.step});
  final int step;

  static const List<String> _statuses = <String>[
    'Saving your thought…',
    'Keeping it safe…',
    'Ready for your inbox.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const PersonaOrb(isPulsing: true),
        SizedBox(height: theme.spacing.xl),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Text(
            _statuses[step.clamp(0, _statuses.length - 1)],
            key: ValueKey<int>(step),
            style: theme.textTheme.titleLarge,
          ),
        ),
      ],
    );
  }
}

class _CaptureErrorOverlay extends StatelessWidget {
  const _CaptureErrorOverlay({required this.code, required this.onDismiss});
  final String? code;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    return Padding(
      padding: EdgeInsets.all(theme.spacing.mobileMargin),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.mic_off_rounded, color: theme.colors.error),
          SizedBox(height: theme.spacing.lg),
          Text(
            'Capture needs your attention.',
            style: theme.textTheme.titleLarge,
          ),
          SizedBox(height: theme.spacing.sm),
          Text(
            code == 'microphone_permission_denied'
                ? 'Allow microphone access in Settings, then try again.'
                : 'Your saved captures are safe. Please try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          SizedBox(height: theme.spacing.xl),
          PillButton(label: 'Close', onPressed: onDismiss),
        ],
      ),
    );
  }
}
