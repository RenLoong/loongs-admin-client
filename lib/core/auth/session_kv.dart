// sessionStorage store + secure-context probe (web); in-memory fallback elsewhere.
export 'session_kv_stub.dart' if (dart.library.js_interop) 'session_kv_web.dart';
