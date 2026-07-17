import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sidekick/app.dart';
import 'package:sidekick/core/capture/capture_permissions.dart';
import 'package:sidekick/core/utils/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeCaptureForegroundRuntime();

  // Restores any cached session from local storage synchronously-fast; does
  // NOT block on a network auth check, so the app can open offline.
  if (AppConfig.hasSupabaseConfiguration) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: AppConfig.supabasePublishableKey,
    );
  }

  runApp(const ProviderScope(child: SidekickApp()));
}
