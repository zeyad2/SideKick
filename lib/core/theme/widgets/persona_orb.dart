import 'package:flutter/material.dart';
import 'package:sidekick/core/theme/app_theme_scope.dart';

class PersonaOrb extends StatefulWidget {
  const PersonaOrb({this.isPulsing = false, super.key});

  final bool isPulsing;

  @override
  State<PersonaOrb> createState() => _PersonaOrbState();
}

class _PersonaOrbState extends State<PersonaOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.9,
    end: 1.08,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(PersonaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPulsing != widget.isPulsing) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;

    return Semantics(
      label: widget.isPulsing ? 'Companion active' : 'Companion',
      child: AnimatedBuilder(
        animation: _scale,
        builder: (BuildContext context, Widget? child) => Transform.scale(
          scale: widget.isPulsing && !MediaQuery.disableAnimationsOf(context)
              ? _scale.value
              : 1,
          child: child,
        ),
        child: SizedBox.square(
          dimension: theme.dimensions.personaOrb,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colors.primaryContainer,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
