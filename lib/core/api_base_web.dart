import 'dart:js_interop';

/// Reads `window.__LOONGS_API_BASE_URL__` set by `domain.js` (same dir as index.html).
@JS('__LOONGS_API_BASE_URL__')
external JSString? get _loongsApiBaseUrl;

String? readRuntimeApiBaseUrl() {
  final v = _loongsApiBaseUrl;
  if (v == null) return null;
  final s = v.toDart.trim();
  if (s.isEmpty) return null;
  return s;
}
