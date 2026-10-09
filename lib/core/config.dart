/// Backend base URL. Override at build/run time:
///   flutter run -d chrome --dart-define=API_BASE_URL=http://192.168.1.10:21000
/// Web builds may use `{host}` (the host the page was loaded from), so one build serves every
/// intranet address / hostname: --dart-define=API_BASE_URL=http://{host}:21000
const String kDefaultApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:21000',
);

/// Web token storage: auto | secure | session | memory.
///  - secure: flutter_secure_storage (WebCrypto-encrypted localStorage; needs a secure context:
///    https or http://localhost / 127.0.0.1).
///  - session: refresh token + pending PKCE in sessionStorage (this tab only, cleared when it is
///    closed), access token in memory only. Works on plain-http intranet origins.
///  - memory: tokens in memory only (reload = sign in again); pending PKCE in sessionStorage.
///  - auto (default): secure when window.isSecureContext, else session.
/// Desktop/mobile always use flutter_secure_storage (Keychain / DPAPI / libsecret).
const String kWebTokenStorage = String.fromEnvironment('WEB_TOKEN_STORAGE', defaultValue: 'auto');

/// Replaces `{host}` in [configured] with [pageHost] (web) or 127.0.0.1 (no page host).
String resolveBaseUrl(String configured, {String? pageHost}) {
  if (!configured.contains('{host}')) return configured;
  var h = (pageHost == null || pageHost.isEmpty) ? '127.0.0.1' : pageHost;
  if (h.contains(':') && !h.startsWith('[')) h = '[$h]'; // IPv6 literal
  return configured.replaceAll('{host}', h);
}

/// Effective web token storage mode for [configured] (see [kWebTokenStorage]).
String resolveWebTokenStorage(String configured, {required bool secureContext}) => switch (configured) {
      'secure' || 'session' || 'memory' => configured,
      _ => secureContext ? 'secure' : 'session',
    };

/// Public OAuth client registered by `./loongs admin:install` (PKCE S256, no secret).
const String kOAuthClientId = String.fromEnvironment(
  'OAUTH_CLIENT_ID',
  defaultValue: 'admin-pc',
);

const String kOAuthScope = 'admin profile';

/// Web redirect target (static page next to index.html, forwards to #/auth/callback).
/// Its absolute URL must be registered on the client (127.0.0.1 loopback: any port).
const String kWebCallbackFile = 'callback.html';
