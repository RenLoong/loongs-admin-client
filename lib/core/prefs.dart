/// Persisted UI preferences (language, theme mode). See [loadPrefs].
library;

export 'prefs_stub.dart' if (dart.library.js_interop) 'prefs_web.dart';

/// Synchronous key/value view over the platform store; writes are persisted in the background.
class PrefsStore {
  PrefsStore([Map<String, String>? values, this._persist]) : _values = values ?? {};

  /// In-memory only (tests, before [loadPrefs] finished).
  PrefsStore.memory() : this();

  final Map<String, String> _values;
  final void Function(String key, String value)? _persist;

  String? get(String key) => _values[key];

  void set(String key, String value) {
    _values[key] = value;
    _persist?.call(key, value);
  }
}

const kPrefLanguage = 'loongs.ui.lang';
const kPrefTheme = 'loongs.ui.theme';
