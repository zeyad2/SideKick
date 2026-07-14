final class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Supabase's modern client-side key (`sb_publishable_…`), the replacement for
  /// the legacy `anon` JWT. Passed to `Supabase.initialize` as `anonKey`, which
  /// accepts either form.
  static const String supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  static bool get hasSupabaseConfiguration =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static bool get hasGeminiConfiguration => geminiApiKey.isNotEmpty;
}
