import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/i18n.dart';
import 'core/prefs.dart';
import 'core/settings.dart';
import 'features/system/role_permission_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSystemCustomPages(); // RENDER.md §9 registered custom pages
  final prefs = await loadPrefs(); // language + theme mode (README §19)
  currentLanguage = normalizeLanguage(prefs.get(kPrefLanguage));

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);
  if (isDesktop) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: tr('LOONGS 平台管理'),
        size: const Size(1280, 800),
        minimumSize: const Size(960, 600),
        center: true,
        titleBarStyle: defaultTargetPlatform == TargetPlatform.windows ? TitleBarStyle.hidden : TitleBarStyle.normal,
        windowButtonVisibility: defaultTargetPlatform != TargetPlatform.windows,
      ),
      () async {
        if (defaultTargetPlatform == TargetPlatform.windows) {
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
        }
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const AdminApp()));
}
