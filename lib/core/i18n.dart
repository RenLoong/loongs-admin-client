/// Client-side translations (README §19).
///
/// Keys are the Chinese source texts (the same convention as the server's loongs/language packs):
/// `tr('保存')` returns the text in the current language, falling back to the source text when the
/// pack has no entry, so a missing key shows the Chinese source text. The default language is en-US (no saved preference, no Accept-Language on the server). `{name}` placeholders are filled from
/// [params]. Server-provided texts (menus, page descriptions, API messages) arrive already
/// translated (the client sends `Accept-Language`), so only the client's own texts live here.
///
/// Add a language: create `i18n_<lang>.dart` with a `Map<String, String>`, register it in
/// [kLanguagePacks] and [kLanguages], and add its [Locale] to [supportedLocales].
library;

import 'package:flutter/widgets.dart';

import 'i18n_en.dart';

const String kDefaultLanguage = 'en-US';

/// Supported languages → endonym (shown in the switchers, never translated).
const Map<String, String> kLanguages = {'zh-CN': '简体中文', 'en-US': 'English'};

/// Short switcher labels.
const Map<String, String> kLanguageShort = {'zh-CN': '中文', 'en-US': 'EN'};

const Map<String, Map<String, String>> kLanguagePacks = {'en-US': kEnUs};

String _current = kDefaultLanguage;

/// Language used by [tr]; set by the app from the persisted settings.
String get currentLanguage => _current;
set currentLanguage(String lang) => _current = normalizeLanguage(lang);

/// `en`, `en_GB`, `EN-us` → `en-US`; `zh`, `zh-Hans` → `zh-CN`; unknown → [kDefaultLanguage].
String normalizeLanguage(String? lang) {
  final v = (lang ?? '').trim().replaceAll('_', '-').toLowerCase();
  if (v.isEmpty) return kDefaultLanguage;
  for (final k in kLanguages.keys) {
    if (k.toLowerCase() == v) return k;
  }
  final primary = v.split('-').first;
  for (final k in kLanguages.keys) {
    if (k.toLowerCase().split('-').first == primary) return k;
  }
  return kDefaultLanguage;
}

/// [lang] → Flutter [Locale] (`zh-CN` → `Locale('zh', 'CN')`).
Locale localeOf(String lang) {
  final p = normalizeLanguage(lang).split('-');
  return Locale(p[0], p.length > 1 ? p[1] : null);
}

List<Locale> get supportedLocales => [for (final l in kLanguages.keys) localeOf(l)];

/// Translates [text] into [lang] (default: [currentLanguage]) and fills `{name}` placeholders.
String tr(String text, [Map<String, Object?> params = const {}, String? lang]) {
  var s = kLanguagePacks[lang ?? _current]?[text] ?? text;
  if (params.isNotEmpty) {
    params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}

/// Keys of [keys] the [lang] pack does not translate (tests / diagnostics).
List<String> missingTranslations(Iterable<String> keys, String lang) {
  final pack = kLanguagePacks[lang];
  if (pack == null) return const [];
  return [for (final k in keys) if (!pack.containsKey(k)) k];
}
