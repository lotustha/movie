/// Backend endpoints and public identifiers. Override at build time with
/// --dart-define=NEXUS_API=https://… to point accounts/sync at another server.
class AppConfig {
  AppConfig._();

  /// ani-nexus: accounts, synced lists/progress, TV sign-in codes.
  static const String nexusApi = String.fromEnvironment(
    'NEXUS_API',
    defaultValue: 'https://mugenstream.fun',
  );

  /// The web OAuth client of Firebase project mugenanime-7482f (from
  /// android/app/google-services.json). Google ID tokens are minted for this
  /// audience, which is the one ani-nexus verifies.
  static const String googleWebClientId =
      '477116627826-21uc8426g8mfqej8bq1d2co8vunasaq3.apps.googleusercontent.com';

  /// Upstream tab with the 18+ ('midnight') rows.
  static const int adultTabId = 9;
}
