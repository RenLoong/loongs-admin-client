import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'custom_page.dart';
import 'form_view.dart';
import 'render_page.dart';
import 'render_repository.dart';
import '../core/i18n.dart';

/// Opens form page [page] as `dialog` | `drawer` | `page` (RENDER.md §5.3 openForm).
/// Resolves to true when the form was submitted successfully. R4: [page] may also be a registered
/// custom page (type `custom`, e.g. role-permission-editor); it closes with `saved` the same way.
Future<bool> openRenderForm(BuildContext context, String page, Map<String, dynamic> params, {String mode = 'dialog'}) async {
  final req = PageRequest(page, params);
  switch (mode) {
    case 'drawer':
      final r = await showShadSheet<bool>(
        context: context,
        side: ShadSheetSide.right,
        builder: (_) => _FormHost(req: req, mode: 'drawer'),
      );
      return r == true;
    case 'page':
      final router = GoRouter.maybeOf(context);
      final uri = Uri(path: '/p/$page', queryParameters: req.params.isEmpty ? null : req.params).toString();
      final r = router != null
          ? await router.push<bool>(uri)
          : await Navigator.of(context).push<bool>(PageRouteBuilder(
              pageBuilder: (_, _, _) => ColoredBox(
                color: ShadTheme.of(context).colorScheme.background,
                child: Padding(padding: const EdgeInsets.all(16), child: RenderPage(page: page, params: req.params, expectType: 'form')),
              ),
            ));
      return r == true;
    default:
      final r = await showShadDialog<bool>(context: context, builder: (_) => _FormHost(req: req, mode: 'dialog'));
      return r == true;
  }
}

/// Dialog / drawer wrapper: fetches the description (ETag cached) and hosts a [FormView].
class _FormHost extends ConsumerWidget {
  const _FormHost({required this.req, required this.mode});

  final PageRequest req;
  final String mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(pageDescProvider(req));
    void close(bool saved) => Navigator.of(context).pop(saved);
    final title = async.value?.title ?? '';
    final Widget content = async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: RenderErrorView(error: e, onRetry: () => ref.invalidate(pageDescProvider(req)))),
      data: (d) => switch (d.type) {
        'form' => FormView(key: ValueKey('form-${d.version}'), desc: d, params: req.params, mode: mode, onClose: close),
        'custom' => buildCustomPage(context, d, params: req.params, mode: mode, onClose: close),
        _ => RenderErrorView(error: tr('页面类型不一致：需要 form，实际 {type}', {'type': d.type})),
      },
    );
    if (mode == 'drawer') {
      return ShadSheet(
        title: Text(title),
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
        scrollable: true,
        child: SizedBox(width: 560, child: content),
      );
    }
    final columns = (async.value?.body['columns'] as num?)?.toInt() ?? 1;
    final custom = async.value?.type == 'custom';
    return ShadDialog(
      title: Text(title),
      constraints: BoxConstraints(maxWidth: custom ? 960 : (columns > 1 ? 720 : 480)),
      child: content,
    );
  }
}

/// Opens detail page [page] (RENDER.md §5.3 openDetail): `page` (default) pushes `/p/{page}?params`
/// (deep-linkable, back returns), `drawer` / `dialog` host the detail in an overlay.
Future<void> openRenderDetail(BuildContext context, String page, Map<String, dynamic> params, {String mode = 'page'}) async {
  final req = PageRequest(page, params);
  Widget body(BuildContext ctx) => RenderPage(page: page, params: req.params, expectType: 'detail');
  switch (mode) {
    case 'drawer':
      await showShadSheet<void>(
        context: context,
        side: ShadSheetSide.right,
        builder: (ctx) => ShadSheet(
          constraints: const BoxConstraints(minWidth: 560, maxWidth: 960),
          child: SizedBox(width: 880, height: MediaQuery.sizeOf(ctx).height - 64, child: body(ctx)),
        ),
      );
    case 'dialog':
      await showShadDialog<void>(
        context: context,
        builder: (ctx) => ShadDialog(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: SizedBox(width: 960, height: MediaQuery.sizeOf(ctx).height * 0.75, child: body(ctx)),
        ),
      );
    default:
      final router = GoRouter.maybeOf(context);
      final uri = Uri(path: '/p/$page', queryParameters: req.params.isEmpty ? null : req.params).toString();
      if (router != null) {
        await router.push<void>(uri);
      } else {
        await Navigator.of(context).push<void>(PageRouteBuilder(
          pageBuilder: (ctx, _, _) => ColoredBox(
            color: ShadTheme.of(ctx).colorScheme.background,
            child: Padding(padding: const EdgeInsets.all(16), child: body(ctx)),
          ),
        ));
      }
  }
}
