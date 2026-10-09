import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/auth/auth_controller.dart';
import 'core/i18n.dart';
import 'core/router.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'widgets/window_caption.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);
    currentLanguage = settings.language;
    // Server-side texts (menus, page descriptions) follow Accept-Language: reload the menus.
    ref.listen(languageProvider, (prev, next) {
      final auth = ref.read(authProvider);
      if (prev != next && auth.status == AuthStatus.signedIn && auth.profile != null) {
        ref.read(authProvider.notifier).loadSession().catchError((_) {});
      }
    });
    return ShadApp.router(
      title: tr('LOONGS 平台管理'),
      debugShowCheckedModeBanner: false,
      locale: localeOf(settings.language),
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme: appleTheme(Brightness.light),
      darkTheme: appleTheme(Brightness.dark),
      // Client texts come from tr(): rebuild the whole tree when the language changes.
      builder: (context, child) {
        final body = KeyedSubtree(key: ValueKey('lang-${settings.language}'), child: child ?? const SizedBox.shrink());
        if (!kWindowsDesktop) return body;
        // Stack keeps the caption above the router for hit-testing.
        return Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: kWindowCaptionHeight),
                child: body,
              ),
            ),
            const Positioned(top: 0, left: 0, right: 0, child: WindowCaption()),
          ],
        );
      },
      routerConfig: router,
    );
  }
}
