import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal string key/value store behind [TokenStore].
abstract class KvStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// flutter_secure_storage (Keychain / DPAPI / libsecret; web: WebCrypto-encrypted localStorage).
class SecureKv implements KvStore {
  SecureKv(this._s);

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemoryKv implements KvStore {
  final Map<String, String> _m = {};

  @override
  Future<String?> read(String key) async => _m[key];

  @override
  Future<void> write(String key, String value) async => _m[key] = value;

  @override
  Future<void> delete(String key) async => _m.remove(key);
}
