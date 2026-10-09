import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import '../core/i18n.dart';

typedef GridRow = Map<String, dynamic>;

/// Frozen (pinned) column side.
enum GridFrozen { start, end }

class GridCol {
  const GridCol(this.title, this.field, {this.width = 120, this.cell, this.text, this.frozen});

  final String title;
  final String field;
  final double width;

  /// Custom cell widget (actions, badges…).
  final Widget Function(GridRow row)? cell;

  /// Custom text value (defaults to row[field]).
  final String Function(GridRow row)? text;

  final GridFrozen? frozen;
}

/// Read-only TrinaGrid over server rows; rebuilt (keyed) whenever [rows] changes.
class AdminGrid extends StatelessWidget {
  const AdminGrid({super.key, required this.columns, required this.rows, this.loading = false});

  final List<GridCol> columns;
  final List<GridRow> rows;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final cs = t.colorScheme;
    return Stack(children: [
      TrinaGrid(
        key: ObjectKey(rows),
        mode: TrinaGridMode.readOnly,
        columns: [
          for (final c in columns)
            TrinaColumn(
              title: c.title,
              field: c.field,
              type: TrinaColumnType.text(),
              width: c.width,
              minWidth: 60,
              readOnly: true,
              enableContextMenu: false,
              enableColumnDrag: false,
              enableDropToResize: false,
              enableSorting: c.cell == null,
              frozen: switch (c.frozen) {
                GridFrozen.start => TrinaColumnFrozen.start,
                GridFrozen.end => TrinaColumnFrozen.end,
                null => TrinaColumnFrozen.none,
              },
              renderer: c.cell == null ? null : (ctx) => c.cell!(ctx.row.data as GridRow),
            ),
        ],
        rows: [
          for (final r in rows)
            TrinaRow<GridRow>(
              data: r,
              cells: {
                for (final c in columns) c.field: TrinaCell(value: c.text?.call(r) ?? _text(r[c.field])),
              },
            ),
        ],
        noRowsWidget: Center(child: Text(tr('暂无数据'))),
        configuration: TrinaGridConfiguration(
          columnSize: const TrinaGridColumnSizeConfig(autoSizeMode: TrinaAutoSizeMode.scale),
          style: TrinaGridStyleConfig(
            gridBackgroundColor: cs.card,
            rowColor: cs.card,
            activatedColor: cs.accent,
            gridBorderColor: const Color(0x00000000),
            borderColor: cs.border,
            activatedBorderColor: cs.ring,
            inactivatedBorderColor: const Color(0x00000000),
            iconColor: cs.mutedForeground,
            enableCellBorderVertical: false,
            rowHeight: 44,
            columnHeight: 40,
            columnTextStyle: t.textTheme.small.copyWith(color: cs.foreground),
            cellTextStyle: t.textTheme.small.copyWith(fontWeight: FontWeight.normal, color: cs.foreground),
          ),
        ),
      ),
      if (loading) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
    ]);
  }

  static String _text(Object? v) => switch (v) {
        null => '',
        List l => l.join(', '),
        _ => '$v',
      };
}

/// Depth-first flattening of `{children: [...]}` trees for grids/selects.
List<(GridRow, int)> flattenTree(List<dynamic> tree, [int depth = 0]) => [
      for (final n in tree) ...[
        ((n as Map).cast<String, dynamic>(), depth),
        ...flattenTree((n['children'] as List?) ?? const [], depth + 1),
      ],
    ];

Widget statusBadge(Object? status) =>
    '$status' == '1' ? ShadBadge(child: Text(tr('启用'))) : ShadBadge.secondary(child: Text(tr('停用')));

class Pager extends StatelessWidget {
  const Pager({super.key, required this.page, required this.pageSize, required this.total, required this.onPage});

  final int page;
  final int pageSize;
  final int total;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        Text(tr('共 {total} 条 · 第 {page} / {pages} 页', {'total': total, 'page': page, 'pages': pages}), style: ShadTheme.of(context).textTheme.muted),
        const SizedBox(width: 8),
        ShadIconButton.outline(
          icon: const Icon(LucideIcons.chevronLeft, size: 16),
          onPressed: page > 1 ? () => onPage(page - 1) : null,
        ),
        const SizedBox(width: 4),
        ShadIconButton.outline(
          icon: const Icon(LucideIcons.chevronRight, size: 16),
          onPressed: page < pages ? () => onPage(page + 1) : null,
        ),
      ]),
    );
  }
}
