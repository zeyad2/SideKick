import 'package:flutter/widgets.dart';
import 'package:sidekick/features/shell/presentation/themed_empty_screen.dart';

class HabitsScreen extends StatelessWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ThemedEmptyScreen(title: 'Habits');
}
