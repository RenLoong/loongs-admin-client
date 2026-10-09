import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'i18n.dart';
import 'prefs.dart';

/// UI settings chosen by the user (language + light / dark / system), persisted locally.
@immutable
class AppSettings {
  const AppSettings({this.language = kDefaultLanguage, this.themeMode = ThemeMode.system});

  final String language;
  final ThemeMode themeMode;

  AppSettings copyWith({String? language, ThemeMode? themeMode}) =>
      AppSettings(language: language ?? this.language, themeMode: themeMode ?? this.themeMode);

  /// `ui_theme` for the server-rendered login page (null = follow the browser).
  String? get uiTheme => switch (themeMode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => null,
      };
}

ThemeMode parseThemeMode(String? v) => switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Overridden in main() with the platform store ([loadPrefs]); memory in tests.
final prefsProvider = Provider<PrefsStore>((ref) => PrefsStore.memory());

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final p = ref.watch(prefsProvider);
    final s = AppSettings(
      language: normalizeLanguage(p.get(kPrefLanguage)),
      themeMode: parseThemeMode(p.get(kPrefTheme)),
    );
    currentLanguage = s.language;
    return s;
  }

  void setLanguage(String lang) {
    final l = normalizeLanguage(lang);
    if (l == state.language) return;
    currentLanguage = l;
    ref.read(prefsProvider).set(kPrefLanguage, l);
    state = state.copyWith(language: l);
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == state.themeMode) return;
    ref.read(prefsProvider).set(kPrefTheme, mode.name);
    state = state.copyWith(themeMode: mode);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Current language (for providers that cache per language).
final languageProvider = Provider<String>((ref) => ref.watch(settingsProvider.select((s) => s.language)));
