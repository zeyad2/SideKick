import 'package:flutter/widgets.dart';
import 'package:sidekick/features/shell/presentation/themed_empty_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ThemedEmptyScreen(title: 'Settings');
}
