import 'package:web/web.dart' as web;

import 'prefs.dart';

/// Web: window.localStorage (per origin, survives reloads and the OAuth redirect).
Future<PrefsStore> loadPrefs() async {
  final s = web.window.localStorage;
  final values = <String, String>{
    for (final k in const [kPrefLanguage, kPrefTheme])
      if (s.getItem(k) case final String v) k: v,
  };
  return PrefsStore(values, (k, v) => s.setItem(k, v));
}
