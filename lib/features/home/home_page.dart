import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/i18n.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(authProvider).profile!;
    final t = ShadTheme.of(context);
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 96, child: Text(k, style: t.textTheme.muted)),
            Expanded(child: Text(v)),
          ]),
        );
    return ListView(children: [
      Text(tr('欢迎，{name}', {'name': p.nickname}), style: t.textTheme.h3),
      const SizedBox(height: 16),
      ShadCard(
        title: Text(tr('当前账号')),
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kv(tr('用户名'), p.username),
            kv(tr('部门'), p.deptName ?? '—'),
            kv(tr('角色'), p.isSuper ? tr('超级管理员') : (p.roles.isEmpty ? '—' : p.roles.join('、'))),
            kv(tr('数据范围'), p.isSuper ? tr('全部数据') : (p.dataScope ?? '—')),
            kv(tr('权限码'), p.isSuper ? tr('*（全部）') : (p.permissions.isEmpty ? '—' : (p.permissions.toList()..sort()).join('\n'))),
            if (p.fields.isNotEmpty) kv(tr('字段权限'), p.fields.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: ShadButton.outline(
          leading: const Icon(LucideIcons.refreshCw, size: 16),
          onPressed: () => ref.read(authProvider.notifier).loadSession(),
          child: Text(tr('刷新权限')),
        ),
      ),
    ]);
  }
}
