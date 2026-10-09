import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../widgets/settings_dialog.dart';
import '../../core/i18n.dart';

IconData menuIcon(String? name) => switch (name) {
      'settings' => LucideIcons.settings,
      'users' => LucideIcons.users,
      'shield' => LucideIcons.shield,
      'menu' => LucideIcons.menu,
      'building' => LucideIcons.building,
      'folder' => LucideIcons.folder,
      'layout-dashboard' => LucideIcons.layoutDashboard,
      'file-text' => LucideIcons.fileText,
      _ => LucideIcons.circle,
    };

/// White sidebar (merchant-admin style) and the server menu tree. Language and appearance
/// live in the settings dialog, opened from the account row (and the Windows caption).
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final theme = ShadTheme.of(context);
    final apple = AppleColors.of(context);
    final p = auth.profile;
    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: Row(
        children: [
          Container(
            width: 208,
            color: apple.sidebar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        color: apple.blue,
                      ),
                      child: const Icon(LucideIcons.layers, size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('LOONGS 平台'),
                          style: theme.textTheme.large.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2), overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                _NavItem(
                  label: tr('首页'),
                  icon: LucideIcons.house,
                  selected: location == '/',
                  onTap: () => context.go('/'),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [for (final m in auth.menus) ..._build(context, m, 0)],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: apple.blue.withValues(alpha: 0.12),
                        child: Text(
                          (p?.nickname.isNotEmpty ?? false) ? p!.nickname.characters.first : '·',
                          style: TextStyle(color: apple.blue, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p?.nickname ?? '…', style: theme.textTheme.small, overflow: TextOverflow.ellipsis),
                            Text(p?.username ?? '', style: theme.textTheme.muted.copyWith(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      Semantics(
                        label: tr('设置'),
                        button: true,
                        excludeSemantics: true,
                        child: ShadIconButton.ghost(
                          key: const ValueKey('open-settings'),
                          icon: const Icon(LucideIcons.settings, size: 16),
                          onPressed: () => showSettingsDialog(context),
                        ),
                      ),
                      Semantics(
                        label: tr('退出登录'),
                        button: true,
                        excludeSemantics: true,
                        child: ShadIconButton.ghost(
                          icon: const Icon(LucideIcons.logOut, size: 16),
                          onPressed: () => ref.read(authProvider.notifier).logout(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: theme.colorScheme.background,
              child: p == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: child),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _build(BuildContext context, MenuNode m, int depth) {
    if (m.isDir) {
      final t = ShadTheme.of(context);
      return [
        Padding(
          padding: EdgeInsets.fromLTRB(18.0 + depth * 12, 16, 12, 4),
          child: Text(m.name, style: t.textTheme.muted.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        for (final c in m.children) ..._build(context, c, depth + 1),
      ];
    }
    return [
      _NavItem(
        label: m.name,
        icon: menuIcon(m.icon),
        indent: depth * 12,
        selected: m.path != null && location == m.path,
        onTap: m.path == null ? null : () => context.go(m.path!),
      ),
    ];
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.icon, required this.selected, this.onTap, this.indent = 0});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final blue = AppleColors.of(context).blue;
    final fg = selected ? blue : t.colorScheme.foreground;
    return Padding(
      padding: EdgeInsets.fromLTRB(8 + indent, 1, 8, 1),
      child: Material(
        color: selected ? blue.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(children: [
              Icon(icon, size: 16, color: selected ? blue : t.colorScheme.mutedForeground),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: t.textTheme.small.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
            ]),
          ),
        ),
      ),
    );
  }
}
