import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'prefs.dart';

/// Desktop / mobile: flutter_secure_storage (the same store as the tokens; tiny, no extra plugin).
Future<PrefsStore> loadPrefs() async {
  const s = FlutterSecureStorage();
  final values = <String, String>{};
  for (final k in const [kPrefLanguage, kPrefTheme]) {
    try {
      final v = await s.read(key: k);
      if (v != null) values[k] = v;
    } catch (_) {}
  }
  return PrefsStore(values, (k, v) => s.write(key: k, value: v).catchError((_) {}));
}
