/// Backend settings come from env.json at build time:
///   flutter run --dart-define-from-file=env.json
/// If they are missing, the app still works fully offline (no friends or leaderboard).
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// Shows the Google button. Turn on only after setting up Google in Supabase (see SETUP.md).
  static const googleSignIn = bool.fromEnvironment('GOOGLE_SIGNIN');

  static bool get hasBackend => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Where Google sign-in and email confirmation links send people back to.
  /// Must match the intent-filter in AndroidManifest.xml and the Supabase redirect URL list.
  static const authRedirect = 'com.madhav.fitlog://login-callback';
}
