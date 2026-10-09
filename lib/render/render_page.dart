import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/auth/auth_controller.dart';
import 'components/unknown.dart';
import 'custom_page.dart';
import 'dashboard_view.dart';
import 'detail_view.dart';
import 'form_view.dart';
import 'render_repository.dart';
import 'table_view.dart';
import '../core/i18n.dart';

/// Generic page (RENDER.md §8.1 PageRenderer): fetches GET /admin/api/pages/{page} (ETag cached)
/// and dispatches on `type`. [expectType] is the menu's `page_type`; a mismatch is an error.
class RenderPage extends ConsumerWidget {
  const RenderPage({super.key, required this.page, this.params = const {}, this.expectType});

  final String page;
  final Map<String, dynamic> params;
  final String? expectType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = PageRequest(page, params);
    return ref.watch(pageDescProvider(req)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RenderErrorView(error: e, onRetry: () => ref.invalidate(pageDescProvider(req))),
          data: (d) {
            // openForm may also open a registered custom page (dialog / drawer / page)
            if (expectType != null && d.type != expectType && !(expectType == 'form' && d.type == 'custom')) {
              return RenderErrorView(error: tr('页面类型不一致：菜单为 {menu}，页面描述为 {type}', {'menu': expectType, 'type': d.type}));
            }
            return KeyedSubtree(
              key: ValueKey('page-${d.page}-${d.version}'),
              child: switch (d.type) {
                'table' => RenderTableView(desc: d, params: req.params),
                'dashboard' => DashboardView(desc: d, params: req.params),
                'detail' => DetailView(desc: d, params: req.params),
                'form' => FormView(
                    desc: d,
                    params: req.params,
                    mode: 'page',
                    onClose: (saved) => Navigator.of(context).maybePop(saved),
                  ),
                'custom' => buildCustomPage(context, d, params: req.params, onClose: (saved) => Navigator.of(context).maybePop(saved)),
                _ => Center(child: UnknownComponent(tr('页面'), d.type)),
              },
            );
          },
        );
  }
}

/// 401 / 403 / 404 / 426 / network errors of the render endpoint.
class RenderErrorView extends ConsumerWidget {
  const RenderErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ShadTheme.of(context);
    final e = error;
    final kind = e is RenderError ? e.kind : RenderErrorKind.invalid;
    final (IconData icon, String title) = switch (kind) {
      RenderErrorKind.unauthorized => (LucideIcons.lock, tr('401 · 登录已失效')),
      RenderErrorKind.forbidden => (LucideIcons.shieldOff, tr('403 · 无权访问此页面')),
      RenderErrorKind.notFound => (LucideIcons.fileQuestion, tr('404 · 页面不存在')),
      RenderErrorKind.upgrade => (LucideIcons.circleArrowUp, tr('426 · 请升级客户端')),
      RenderErrorKind.network => (LucideIcons.wifiOff, tr('网络错误')),
      RenderErrorKind.invalid => (LucideIcons.triangleAlert, tr('页面加载失败')),
    };
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 28, color: t.colorScheme.mutedForeground),
        const SizedBox(height: 8),
        Text(title, style: t.textTheme.large),
        const SizedBox(height: 4),
        Text('$e', style: t.textTheme.muted, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        if (kind == RenderErrorKind.unauthorized)
          ShadButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: Text(tr('重新登录')))
        else if (onRetry != null && kind != RenderErrorKind.forbidden && kind != RenderErrorKind.upgrade)
          ShadButton.outline(onPressed: onRetry, child: Text(tr('重试'))),
      ]),
    );
  }
}

