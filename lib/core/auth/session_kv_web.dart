import 'package:web/web.dart' as web;

import 'kv_store.dart';

class _SessionKv implements KvStore {
  @override
  Future<String?> read(String key) async => web.window.sessionStorage.getItem(key);

  @override
  Future<void> write(String key, String value) async => web.window.sessionStorage.setItem(key, value);

  @override
  Future<void> delete(String key) async => web.window.sessionStorage.removeItem(key);
}

/// window.sessionStorage: per tab, survives reloads and same-tab redirects, gone when the tab closes.
KvStore sessionKv() => _SessionKv();

/// false on plain-http origins other than localhost (no WebCrypto → no flutter_secure_storage).
bool isSecureContext() => web.window.isSecureContext;
