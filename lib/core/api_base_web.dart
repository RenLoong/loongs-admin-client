import 'dart:js_interop';

/// Reads `window.__LOONGS_API_BASE_URL__` injected by admin `ClientEntry`
/// (first origin in `OAUTH_ALLOWED_ORIGINS`) into the packed SPA shell.
/// Local `flutter run` without PHP leaves this null → dart-define / `{host}` fallback.
@JS('__LOONGS_API_BASE_URL__')
external JSString? get _loongsApiBaseUrl;

String? readRuntimeApiBaseUrl() {
  final v = _loongsApiBaseUrl;
  if (v == null) return null;
  final s = v.toDart.trim();
  if (s.isEmpty) return null;
  return s;
}
