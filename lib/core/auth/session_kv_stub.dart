import 'kv_store.dart';

/// Not on web: there is no sessionStorage (desktop/mobile use flutter_secure_storage).
KvStore sessionKv() => MemoryKv();

bool isSecureContext() => true;
