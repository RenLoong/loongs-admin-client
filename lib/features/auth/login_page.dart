import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api_client.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/ui_settings.dart';

/// Sign-in entry. Credentials are entered only on the server's /oauth/authorize page
/// (authorization code + PKCE), never inside the app. The chosen language / theme are passed on
/// (ui_locales / ui_theme), so the server page matches.
class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final theme = ShadTheme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF0B1A33), Color(0xFF1A1030), Color(0xFF000000)]
                : const [Color(0xFFDDEBFF), Color(0xFFF1E6FF), Color(0xFFF2F2F7)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Color(0xFF34AADC), Color(0xFF007AFF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                        boxShadow: appleShadow(theme.brightness),
                      ),
                      child: const Icon(LucideIcons.layers, size: 32, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(tr('LOONGS 平台管理'),
                      textAlign: TextAlign.center, style: theme.textTheme.h3.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4)),
                  const SizedBox(height: 6),
                  Text(
                    kIsWeb ? tr('将跳转到认证中心登录（授权码 + PKCE）') : tr('将在系统浏览器中打开认证中心登录，完成后自动返回'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.muted,
                  ),
                  const SizedBox(height: 22),
                  ShadCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (auth.error != null) ...[
                          ShadAlert.destructive(title: Text(tr('未登录')), description: Text(auth.error!)),
                          const SizedBox(height: 14),
                        ],
                        ShadButton(
                          size: ShadButtonSize.lg,
                          onPressed: auth.busy ? null : () => ref.read(authProvider.notifier).login(),
                          leading: auth.busy
                              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(LucideIcons.logIn, size: 16),
                          child: Text(auth.busy ? (kIsWeb ? tr('正在跳转…') : tr('等待浏览器完成登录…')) : tr('登录')),
                        ),
                        const SizedBox(height: 20),
                        Row(children: [
                          Text(tr('语言'), style: theme.textTheme.small),
                          const Spacer(),
                          const LanguageSwitch(),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Text(tr('外观'), style: theme.textTheme.small),
                          const Spacer(),
                          const ThemeModeSwitch(),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(tr('服务端：{url}', {'url': ref.watch(baseUrlProvider)}), textAlign: TextAlign.center, style: theme.textTheme.muted.copyWith(fontSize: 12)),
                  Center(
                    child: ShadButton.link(
                      onPressed: () => context.go('/health'),
                      child: Text(tr('检查后端健康状态')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}
