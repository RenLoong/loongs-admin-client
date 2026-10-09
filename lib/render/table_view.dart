import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../widgets/admin_grid.dart';
import '../widgets/common.dart';
import 'action_runner.dart';
import 'components/cells.dart';
import 'components/fields.dart';
import 'page_desc.dart';
import 'render_api.dart';
import 'template.dart';
import '../core/i18n.dart';

/// Table page (RENDER.md §6.3): search bar, toolbar, trina_grid with row actions, pager, optional
/// multi-select for batch actions. Request: `page`, `page_size`, non-empty search values.
/// R4: `tree` (whole tree from the API, rows indented in the tree column, collapsible, no pager),
/// `pagination: false` (full list, no pager) and `notice` (text above the grid, `{field}`s filled
/// from the object its `api` returns).
class RenderTableView extends ConsumerStatefulWidget {
  const RenderTableView({super.key, required this.desc, this.params = const {}, this.embedded = false});

  final PageDesc desc;

  /// Fixed query params sent with every data request (e.g. `tenant_id` of a detail page's
  /// `Block::table(page, ['tenant_id' => '{id}'])`); search values cannot override them.
  final Map<String, dynamic> params;

  /// Inside a detail / dashboard block: compact header (no page title).
  final bool embedded;

  @override
  ConsumerState<RenderTableView> createState() => _RenderTableViewState();
}

class _RenderTableViewState extends ConsumerState<RenderTableView> {
  final FormController _search = FormController();
  late final FieldEnv _env = FieldEnv(ref.read(renderApiProvider));
  PageResult? _data;
  List<Json> _all = const [];
  List<Json> _rows = const [];
  final Set<String> _collapsed = {};
  String? _notice;
  bool _loading = false;
  int _page = 1;
  final Set<String> _selected = {};

  Json get _body => widget.desc.body;
  String get _rowKey => '${_body['rowKey'] ?? 'id'}';
  int get _pageSize => ((_body['pageSizes'] as List?)?.firstOrNull as num?)?.toInt() ?? 20;
  Json? get _tree => _body['tree'] is Map ? asJson(_body['tree']) : null;
  bool get _paged => _tree == null && _body['pagination'] != false;
  String get _childrenKey => '${_tree?['children'] ?? 'children'}';

  @override
  void initState() {
    super.initState();
    _load();
    _loadNotice();
  }

  Future<void> _loadNotice() async {
    final n = asJson(_body['notice']);
    final msg = n['message'];
    if (msg is! String) return;
    if (n['api'] is! String) {
      setState(() => _notice = fillText(msg, widget.params));
      return;
    }
    final api = fillPath(n['api'] as String, widget.params);
    if (api == null) return;
    try {
      final data = await ref.read(renderApiProvider).get(api);
      if (mounted) setState(() => _notice = fillText(msg, {...widget.params, ...asJson(data)}));
    } catch (_) {
      // the notice is informative only; the grid still works without it
    }
  }

  /// Depth-first rows of a tree response: `_depth`, `_leaf` added, children removed (they are rows).
  List<Json> _flatten(Object? nodes, int depth, bool collapsedByDefault, [String prefix = '']) {
    final out = <Json>[];
    final list = asJsonList(nodes);
    for (var i = 0; i < list.length; i++) {
      final n = list[i];
      final kids = asJsonList(n[_childrenKey]);
      final row = {...n}..remove(_childrenKey);
      row['_depth'] = depth;
      row['_leaf'] = kids.isEmpty;
      // tree key: rowKey value, or the position for nodes without one (e.g. menu dirs without perms)
      final key = row[_rowKey] == null || '${row[_rowKey]}' == '' ? '#$prefix$i' : '${row[_rowKey]}';
      row['_key'] = key;
      if (collapsedByDefault && kids.isNotEmpty) _collapsed.add(key);
      out
        ..add(row)
        ..addAll(_flatten(kids, depth + 1, collapsedByDefault, '$prefix$i.'));
    }
    return out;
  }

  /// Rows shown by the grid: the same list instance until data or the collapse state changes
  /// (the grid is keyed by its rows, so a new list would rebuild it).
  void _syncRows() => _rows = _tree != null ? _visibleTreeRows() : _all;

  void _toggle(String key) => setState(() {
        _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key);
        _syncRows();
      });

  /// Visible rows of a tree table (descendants of collapsed rows hidden).
  List<Json> _visibleTreeRows() {
    final out = <Json>[];
    int? hideBelow;
    for (final r in _all) {
      final d = (r['_depth'] as int?) ?? 0;
      if (hideBelow != null && d > hideBelow) continue;
      hideBelow = _collapsed.contains('${r['_key']}') ? d : null;
      out.add(r);
    }
    return out;
  }

  Map<String, dynamic> _query({int? page}) => {
        if (_paged) ...{'page': page ?? _page, 'page_size': _pageSize},
        for (final e in _search.values.entries)
          if (e.value != null && '${e.value}'.trim().isNotEmpty) e.key: e.value is String ? (e.value as String).trim() : e.value,
        for (final e in widget.params.entries)
          if (e.value != null && '${e.value}' != '') e.key: e.value,
      };

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load([int? page]) async {
    final api = _body['api'];
    if (api is! String) return;
    setState(() => _loading = true);
    await runAction(context, () async {
      if (_paged) {
        final r = await ref.read(renderApiProvider).page(api, query: _query(page: page));
        _data = r;
        _page = r.page;
        _all = r.list;
      } else {
        final r = await ref.read(renderApiProvider).get(api, query: _query());
        final list = r is Map ? (r['list'] ?? const []) : r;
        final first = _all.isEmpty;
        _all = _tree != null ? _flatten(list, 0, first && _tree!['expanded'] == false) : asJsonList(list);
        _data = null;
      }
      _syncRows();
      _selected.clear();
    });
    if (mounted) setState(() => _loading = false);
  }

  ActionRunner _runner() => ActionRunner(
        context: context,
        ref: ref,
        onRefresh: () => _load(),
        selection: [
          for (final r in _all)
            if (_selected.contains('${r[_rowKey]}')) r[_rowKey],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cs = ShadTheme.of(context).colorScheme;
    final columns = asJsonList(_body['columns']);
    final rowActions = asJsonList(_body['rowActions']);
    final toolbar = asJsonList(_body['toolbar']);
    final search = asJsonList(_body['search']);
    final selection = _body['selection'] == true;
    final rows = _rows;
    final treeColumn = _tree == null ? null : '${_tree!['column'] ?? columns.firstOrNull?['field'] ?? ''}';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!widget.embedded || toolbar.isNotEmpty)
        PageHeader(title: widget.embedded ? '' : widget.desc.title, actions: [
          for (final a in toolbar)
            if (actionVisible(a, widget.params)) actionButton(a, () => _runner().run(a, widget.params)),
        ]),
      if (_notice != null && _notice!.isNotEmpty)
        Container(
          key: const ValueKey('table-notice'),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: ShadTheme.of(context).brightness == Brightness.dark ? const Color(0xFF3A2E12) : const Color(0xFFFFF7E8),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_noticeIcon('${asJson(_body['notice'])['type']}'), size: 16, color: cs.mutedForeground),
            const SizedBox(width: 8),
            Expanded(child: Text(_notice!, style: TextStyle(color: cs.mutedForeground, fontSize: 13))),
          ]),
        ),
      if (search.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final f in search) SizedBox(width: 200, child: buildField(context, f, _search, _env, dense: true)),
            ShadButton(onPressed: () => _load(1), child: Text(tr('查询'))),
            ShadButton.outline(
              onPressed: () {
                _search.reset({});
                _load(1);
              },
              child: Text(tr('重置')),
            ),
          ]),
        ),
      Expanded(
        child: AdminGrid(
          loading: _loading,
          rows: rows,
          columns: [
            if (selection)
              GridCol('', '_select', width: 48, frozen: GridFrozen.start, cell: (r) {
                final k = '${r[_rowKey]}';
                return StatefulBuilder(builder: (context, set) {
                  void toggle(bool on) {
                    set(() => on ? _selected.add(k) : _selected.remove(k));
                    setState(() {});
                  }

                  return GestureDetector(
                    key: ValueKey('select-$k'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => toggle(!_selected.contains(k)),
                    child: Align(alignment: Alignment.centerLeft, child: ShadCheckbox(value: _selected.contains(k), onChanged: toggle)),
                  );
                });
              }),
            for (final c in columns)
              GridCol(
                '${c['label']}${c['masked'] == true ? tr('（脱敏）') : ''}',
                '${c['field']}',
                width: (c['width'] as num?)?.toDouble() ?? 120,
                frozen: c['fixed'] == 'left' ? GridFrozen.start : (c['fixed'] == 'right' ? GridFrozen.end : null),
                text: (r) => columnText(c, r),
                cell: '${c['field']}' == treeColumn
                    ? (r) => _treeCell(context, c, r)
                    : c['component'] == 'text' || c['component'] == 'datetime' || c['component'] == 'money'
                        ? null
                        : (r) => buildCell(context, c, r),
              ),
            if (rowActions.isNotEmpty)
              GridCol(tr('操作'), '_actions', width: (rowActions.length * 76 + 24).toDouble(), cell: (r) => Row(children: [
                    for (final a in rowActions)
                      if (actionVisible(a, r))
                        actionButton(a, () => _runner().run(a, r), link: true, label: fillText('${a['label']}', r)),
                  ])),
          ],
        ),
      ),
      if (_paged && _data != null)
        Row(children: [
          if (selection && _selected.isNotEmpty) Text(tr('已选 {n} 条', {'n': _selected.length}), style: TextStyle(color: cs.mutedForeground, fontSize: 12)),
          Expanded(child: Pager(page: _data!.page, pageSize: _data!.pageSize, total: _data!.total, onPage: _load)),
        ]),
    ]);
  }

  /// Tree column: indentation + expand / collapse toggle (leaf rows get a spacer).
  Widget _treeCell(BuildContext context, Json c, Json r) {
    final cs = ShadTheme.of(context).colorScheme;
    final k = '${r['_key']}';
    final depth = (r['_depth'] as int?) ?? 0;
    final open = !_collapsed.contains(k);
    final plain = c['component'] == 'text' || c['component'] == 'datetime' || c['component'] == 'money';
    return Row(children: [
      SizedBox(width: depth * 18.0),
      if (r['_leaf'] == true)
        const SizedBox(width: 22)
      else
        GestureDetector(
          key: ValueKey('tree-toggle-$k'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _toggle(k),
          child: SizedBox(
            width: 22,
            child: Icon(open ? LucideIcons.chevronDown : LucideIcons.chevronRight, size: 16, color: cs.mutedForeground),
          ),
        ),
      Expanded(
        child: plain ? Text(columnText(c, r), overflow: TextOverflow.ellipsis) : buildCell(context, c, r),
      ),
    ]);
  }

  static IconData _noticeIcon(String type) => switch (type) {
        'warning' => LucideIcons.triangleAlert,
        'error' => LucideIcons.circleX,
        'success' => LucideIcons.circleCheck,
        _ => LucideIcons.info,
      };
}
