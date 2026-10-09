import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/i18n.dart';
import '../core/settings.dart';
import '../core/theme.dart';

/// iOS segmented control in the app's colors.
class AppleSegmented<T extends Object> extends StatelessWidget {
  const AppleSegmented({super.key, required this.value, required this.items, required this.onChanged, this.semanticsLabel});

  final T value;
  final Map<T, Widget> items;
  final ValueChanged<T> onChanged;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = AppleColors.of(context);
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    final control = CupertinoSlidingSegmentedControl<T>(
      groupValue: value,
      backgroundColor: dark ? const Color(0xFF2C2C2E) : const Color(0x1F767680),
      thumbColor: dark ? const Color(0xFF636366) : Colors.white,
      padding: const EdgeInsets.all(2),
      children: {
        for (final e in items.entries)
          e.key: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: c.label, fontWeight: FontWeight.w500),
            child: IconTheme.merge(data: IconThemeData(color: c.label, size: 14), child: e.value),
          ),
      },
      onValueChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    return semanticsLabel == null ? control : Semantics(label: semanticsLabel, container: true, child: control);
  }
}

/// 中文 | EN (persisted; also re-translates server texts via Accept-Language).
class LanguageSwitch extends ConsumerWidget {
  const LanguageSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    return AppleSegmented<String>(
      key: const ValueKey('language-switch'),
      semanticsLabel: tr('切换语言'),
      value: lang,
      items: {
        for (final e in kLanguageShort.entries)
          e.key: Semantics(label: kLanguages[e.key], excludeSemantics: true, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(e.value))),
      },
      onChanged: (v) => ref.read(settingsProvider.notifier).setLanguage(v),
    );
  }
}

/// Light | Dark | System (persisted).
class ThemeModeSwitch extends ConsumerWidget {
  const ThemeModeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    Widget item(IconData icon, String label) => Semantics(
          label: label,
          excludeSemantics: true,
          child: Tooltip(message: label, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), child: Icon(icon))),
        );
    return AppleSegmented<ThemeMode>(
      key: const ValueKey('theme-switch'),
      semanticsLabel: tr('切换外观'),
      value: mode,
      items: {
        ThemeMode.light: item(LucideIcons.sun, tr('浅色')),
        ThemeMode.dark: item(LucideIcons.moon, tr('深色')),
        ThemeMode.system: item(LucideIcons.monitor, tr('跟随系统')),
      },
      onChanged: (v) => ref.read(settingsProvider.notifier).setThemeMode(v),
    );
  }
}
