import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../chart/chart_format.dart';
import '../chart/chart_spec.dart';
import '../page_desc.dart';
import '../template.dart';
import 'unknown.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

typedef CellBuilder = Widget Function(BuildContext context, Json column, Json row);

/// Text of a cell value: lists of `{name|label}` maps are joined (e.g. roles → "管理员、运维").
String cellText(Object? v) => switch (v) {
      null => '',
      List l => l.map((e) => e is Map ? '${e['label'] ?? e['name'] ?? e['title'] ?? e['value'] ?? ''}' : '$e').where((s) => s.isNotEmpty).join('、'),
      Map m => '${m['label'] ?? m['name'] ?? m['title'] ?? ''}',
      bool b => b ? tr('是') : tr('否'),
      _ => '$v',
    };

/// Plain text used for the grid cell value (sorting / copy) of a column.
String columnText(Json c, Json row) {
  final v = lookup(row, '${c['field']}');
  final empty = '${c['emptyText'] ?? ''}';
  final s = switch ('${c['component']}') {
    'datetime' => formatDateTime(v, c['format'] as String?),
    'tag' || 'badge' => _option(c, v)?.label ?? cellText(v),
    'money' => v == null || v == '' ? '' : (num.tryParse('$v')?.toStringAsFixed(2) ?? '$v'),
    'bool' => v == null ? '' : (sameValue(v, true) ? tr('是') : tr('否')),
    _ => cellText(v),
  };
  if (s.isEmpty) return empty;
  // `format` template ({value|money:CNY}, {value} 席 …) for non-date columns (RENDER.md §6.1.1 formats).
  final f = c['format'];
  if (f is String && f.contains('{') && c['component'] != 'datetime' && c['component'] != 'tag' && c['component'] != 'badge') {
    return formatTemplate(f, {'value': v});
  }
  return s;
}

OptionItem? _option(Json c, Object? v) {
  for (final o in OptionItem.listFrom(c['options'])) {
    if (sameValue(o.value, v)) return o;
  }
  return null;
}

/// Option color (success | warning | danger | info | primary | default | #rrggbb) → badge.
Widget optionBadge(BuildContext context, String label, String? color) {
  final cs = ShadTheme.of(context).colorScheme;
  final apple = AppleColors.of(context);
  final Color? bg = switch (color) {
    'success' => apple.green,
    'warning' => apple.orange,
    'danger' => cs.destructive,
    'info' => apple.teal,
    'primary' => cs.primary,
    final String c when c.contains('|') => parseColor(c, dark: ShadTheme.of(context).brightness == Brightness.dark),
    final String c when RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(c) => Color(int.parse('FF${c.substring(1)}', radix: 16)),
    _ => null,
  };
  if (bg == null) return ShadBadge.secondary(child: Text(label));
  return ShadBadge(backgroundColor: bg, hoverBackgroundColor: bg, foregroundColor: Colors.white, child: Text(label));
}

Widget _text(BuildContext context, String s) =>
    Align(alignment: Alignment.centerLeft, child: Text(s, overflow: TextOverflow.ellipsis, style: ShadTheme.of(context).textTheme.small.copyWith(fontWeight: FontWeight.normal)));

/// Column renderers (RENDER.md §7 列/展示). Unknown components fall back to [UnknownComponent].
final Map<String, CellBuilder> columnRegistry = {
  'text': (ctx, c, r) => _text(ctx, columnText(c, r)),
  'datetime': (ctx, c, r) => _text(ctx, columnText(c, r)),
  'money': (ctx, c, r) => _text(ctx, columnText(c, r)),
  'tag': (ctx, c, r) {
    final v = lookup(r, '${c['field']}');
    if (v == null || v == '') return _text(ctx, '${c['emptyText'] ?? ''}');
    final o = _option(c, v);
    return Align(alignment: Alignment.centerLeft, child: optionBadge(ctx, o?.label ?? cellText(v), o?.color));
  },
  'badge': (ctx, c, r) {
    final v = lookup(r, '${c['field']}');
    final o = _option(c, v);
    return Align(alignment: Alignment.centerLeft, child: optionBadge(ctx, o?.label ?? cellText(v), o?.color ?? 'primary'));
  },
  'bool': (ctx, c, r) {
    final v = lookup(r, '${c['field']}');
    if (v == null) return const SizedBox.shrink();
    return Align(alignment: Alignment.centerLeft, child: Icon(sameValue(v, true) ? LucideIcons.check : LucideIcons.x, size: 16));
  },
  'copyable': (ctx, c, r) {
    final s = columnText(c, r);
    return Row(children: [
      Flexible(child: _text(ctx, s)),
      if (s.isNotEmpty && c['masked'] != true)
        ShadIconButton.ghost(
          width: 24,
          height: 24,
          icon: const Icon(LucideIcons.copy, size: 12),
          onPressed: () => Clipboard.setData(ClipboardData(text: s)),
        ),
    ]);
  },
  'progress': (ctx, c, r) {
    final v = num.tryParse('${lookup(r, '${c['field']}') ?? ''}');
    if (v == null) return const SizedBox.shrink();
    final p = (v > 1 ? v / 100 : v).clamp(0, 1).toDouble();
    return Row(children: [
      Expanded(child: ShadProgress(value: p)),
      const SizedBox(width: 6),
      Text('${(p * 100).round()}%', style: const TextStyle(fontSize: 12)),
    ]);
  },
  'image': (ctx, c, r) {
    final url = '${lookup(r, '${c['field']}') ?? ''}';
    if (!url.startsWith('http')) return _text(ctx, url);
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.network(url, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(LucideIcons.imageOff, size: 16)),
    );
  },
  'link': (ctx, c, r) => _text(ctx, columnText(c, r)),
};

/// Column cell (unknown component → compact placeholder, never a crash).
Widget buildCell(BuildContext context, Json column, Json row) {
  final b = columnRegistry['${column['component']}'];
  if (b == null) return UnknownComponent(tr('列'), '${column['component']}', compact: true);
  return b(context, column, row);
}
