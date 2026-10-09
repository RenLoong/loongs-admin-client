import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../core/auth/auth_controller.dart';
import '../core/i18n.dart';

void showToast(BuildContext context, String message, {bool error = false}) {
  final t = ShadToaster.maybeOf(context);
  if (t == null) return;
  t.show(error
      ? ShadToast.destructive(description: Text(message))
      : ShadToast(description: Text(message)));
}

/// Runs [action]; shows the server `message` on success/failure. Returns true on success.
Future<bool> runAction(BuildContext context, Future<dynamic> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showToast(context, success);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      final details = e.errors.values.expand((v) => v).join('；');
      showToast(context, details.isEmpty ? e.message : '${e.message}：$details', error: true);
    }
    return false;
  }
}

Future<bool> confirmDialog(BuildContext context, String title, String description) async {
  final ok = await showShadDialog<bool>(
    context: context,
    builder: (c) => ShadDialog.alert(
      title: Text(title),
      description: Text(description),
      actions: [
        ShadButton.outline(child: Text(tr('取消')), onPressed: () => Navigator.of(c).pop(false)),
        ShadButton.destructive(child: Text(tr('确定')), onPressed: () => Navigator.of(c).pop(true)),
      ],
    ),
  );
  return ok ?? false;
}

/// Renders [child] only when the current admin holds [code] (button permission).
class Can extends ConsumerWidget {
  const Can(this.code, {super.key, required this.child});

  final String code;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(authProvider.select((s) => s.can(code))) ? child : const SizedBox.shrink();
}

class FormRow extends StatelessWidget {
  const FormRow(this.label, this.child, {super.key, this.hint});

  final String label;
  final Widget child;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(label, style: t.textTheme.small),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                child,
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(hint!, style: t.textTheme.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple select over (value,label) pairs.
class OptionSelect<T> extends StatelessWidget {
  const OptionSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder = '请选择',
    this.enabled = true,
  });

  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    String labelOf(T v) => options.firstWhere((o) => o.$1 == v, orElse: () => (v, '$v')).$2;
    return ShadSelect<T>(
      key: ValueKey('sel-$value-${options.length}'),
      enabled: enabled,
      minWidth: 240,
      initialValue: value,
      placeholder: Text(tr(placeholder)),
      options: [for (final o in options) ShadOption<T>(value: o.$1, child: Text(o.$2))],
      selectedOptionBuilder: (_, v) => Text(labelOf(v)),
      onChanged: onChanged,
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.actions = const []});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(title, style: ShadTheme.of(context).textTheme.h4),
          const Spacer(),
          ...actions.expand((w) => [w, const SizedBox(width: 8)]),
        ],
      ),
    );
  }
}

class ForbiddenPage extends StatelessWidget {
  const ForbiddenPage({super.key});

  @override
  Widget build(BuildContext context) => Center(child: Text(tr('403 · 无权访问此页面')));
}

class NotFoundPage extends StatelessWidget {
  const NotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => Center(child: Text(tr('404 · 页面不存在（菜单已配置但前端页面尚未实现）')));
}
