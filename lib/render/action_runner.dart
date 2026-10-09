import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../widgets/common.dart';
import 'form_host.dart';
import 'page_desc.dart';
import 'render_api.dart';
import 'template.dart';
import '../core/i18n.dart';

/// Executes the actions of RENDER.md §5.3 (openForm, openDetail, request, batchRequest, navigate,
/// refresh [target], submit, close; export / import degrade to a notice until P2) with confirm
/// dialogs, success toasts and `then: refresh | close | navigate | toast`.
class ActionRunner {
  ActionRunner({
    required this.context,
    required this.ref,
    this.onRefresh,
    this.onRefreshTarget,
    this.onClose,
    this.onSubmit,
    this.selection = const [],
  });

  final BuildContext context;
  final WidgetRef ref;

  /// Reload the current table / record.
  final VoidCallback? onRefresh;

  /// `refresh` with a `target` block id (dashboard / detail); falls back to [onRefresh].
  final void Function(String target)? onRefreshTarget;

  /// Close the hosting dialog / drawer / page (forms).
  final VoidCallback? onClose;

  /// Form submit (the form validates and sends; returns true on success).
  final Future<bool> Function(Json action)? onSubmit;

  /// Selected rowKey values (batchRequest).
  final List<Object?> selection;

  static const _unsupported = {'export', 'import'};

  /// Runs [action] against [data] (row / record / params). Returns true when it completed.
  Future<bool> run(Json action, [Json data = const {}]) async {
    final kind = '${action['action']}';
    switch (kind) {
      case 'openForm':
        final saved = await openRenderForm(
          context,
          '${action['page']}',
          fillParams(action['params'], data),
          mode: '${action['mode'] ?? 'dialog'}',
        );
        if (saved && onRefresh != null) onRefresh!();
        return saved;
      case 'openDetail':
        await openRenderDetail(
          context,
          '${action['page']}',
          fillParams(action['params'], data),
          mode: '${action['mode'] ?? 'page'}',
        );
        if (action['then'] == 'refresh') onRefresh?.call();
        return true;
      case 'request':
      case 'batchRequest':
        return _request(action, data, batch: kind == 'batchRequest');
      case 'navigate':
        final path = fillPath('${action['path']}', data);
        if (path == null) return false;
        final q = fillParams(action['query'], data).map((k, v) => MapEntry(k, '${v ?? ''}'));
        if (context.mounted) GoRouter.maybeOf(context)?.go(Uri(path: path, queryParameters: q.isEmpty ? null : q).toString());
        return true;
      case 'refresh':
        final target = action['target'];
        if (target is String && target.isNotEmpty && onRefreshTarget != null) {
          onRefreshTarget!(target);
        } else {
          onRefresh?.call();
        }
        return true;
      case 'submit':
        return onSubmit != null && await onSubmit!(action);
      case 'close':
        onClose?.call();
        return true;
      default:
        if (context.mounted) {
          showToast(context, _unsupported.contains(kind) ? tr('当前客户端暂不支持该操作（{kind}）', {'kind': kind}) : tr('当前客户端版本不支持该操作，请升级'), error: true);
        }
        return false;
    }
  }

  Future<bool> _request(Json action, Json data, {required bool batch}) async {
    if (batch && selection.isEmpty) {
      showToast(context, tr('请先选择数据'), error: true);
      return false;
    }
    final api = fillPath('${action['api']}', data);
    if (api == null) {
      showToast(context, tr('缺少参数，无法执行“{label}”', {'label': action['label']}), error: true);
      return false;
    }
    final confirm = action['confirm'];
    if (confirm is String) {
      final text = batch ? '${fillText(confirm, data)}${tr('（已选 {n} 条）', {'n': selection.length})}' : fillText(confirm, data);
      if (!await confirmDialog(context, fillText('${action['label']}', data), text)) return false;
    }
    if (!context.mounted) return false;
    final body = batch ? {'ids': selection} : (action['body'] == null ? null : fillValue(action['body'], data));
    final ok = await runAction(
      context,
      () => ref.read(renderApiProvider).send('${action['method'] ?? 'POST'}', api, body: body),
      success: '${action['message'] ?? tr('操作成功')}',
    );
    if (ok) _then(action, data);
    return ok;
  }

  void _then(Json action, Json data) {
    switch (action['then']) {
      case 'refresh':
        onRefresh?.call();
      case 'close':
        onClose?.call();
      case 'navigate':
        final p = fillPath('${action['thenPath']}', data);
        if (p != null && context.mounted) GoRouter.maybeOf(context)?.go(p);
    }
  }
}

/// Button for one action (primary / danger / link styles).
Widget actionButton(Json a, VoidCallback? onPressed, {bool link = false, String? label}) {
  final text = Text(label ?? '${a['label']}');
  final icon = a['icon'] == 'plus' ? const Icon(LucideIcons.plus, size: 16) : null;
  if (link) {
    return ShadButton.link(size: ShadButtonSize.sm, onPressed: onPressed, child: text);
  }
  if (a['danger'] == true) return ShadButton.destructive(leading: icon, onPressed: onPressed, child: text);
  if (a['primary'] == true) return ShadButton(leading: icon, onPressed: onPressed, child: text);
  return ShadButton.outline(leading: icon, onPressed: onPressed, child: text);
}
