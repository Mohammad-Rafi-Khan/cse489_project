/// Supabase configuration for RetailFlow.
///
/// These values come from:
///   Supabase Dashboard → Settings → API
///
/// The URL and anon key are safe to commit to version control
/// (they are public-facing). NEVER paste the service_role key here.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = 'https://eafefastkvyeufajjukv.supabase.co';

  /// Public / anon key — safe to include in client apps.
  static const String anonKey =
      'sb_publishable_zaD-1UM4FZSc7BKCYUoXww_WST6HOTN';
}
