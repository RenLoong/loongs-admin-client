import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/i18n.dart';

/// Placeholder for a component / page type this client does not know (RENDER.md §7):
/// debug builds show a red box naming it, release builds ask the user to upgrade. Never throws.
class UnknownComponent extends StatelessWidget {
  const UnknownComponent(this.kind, this.name, {super.key, this.compact = false});

  /// `column` | `field` | `action` | `page` …
  final String kind;
  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final text = kReleaseMode ? tr('当前客户端版本不支持该内容，请升级') : tr('未支持的{kind}组件：{name}', {'kind': tr(kind), 'name': name});
    final style = TextStyle(fontSize: 12, color: kReleaseMode ? cs.mutedForeground : cs.destructive);
    if (compact) return Text(text, style: style, overflow: TextOverflow.ellipsis);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: kReleaseMode ? cs.border : cs.destructive),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: style),
    );
  }
}
