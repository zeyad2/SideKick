import 'package:flutter/widgets.dart';

/// Phase 0 API stub. Phase 5 will add token-driven particles and completion.
class ParticleBurst extends StatelessWidget {
  const ParticleBurst({
    required this.child,
    this.isActive = false,
    this.onComplete,
    super.key,
  });

  final Widget child;
  final bool isActive;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) => child;
}
