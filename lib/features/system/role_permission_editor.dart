import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api.dart';
import '../../render/custom_page.dart';
import '../../render/page_desc.dart';
import '../../render/render_api.dart';
import '../../widgets/admin_grid.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';

/// Custom component name of the server page admin.system.role-permissions (RENDER.md §9).
const kRolePermissionEditor = 'role-permission-editor';

/// Registers the P1 custom pages (the only hand-written system pages left after R4).
void registerSystemCustomPages() {
  registerCustomPage(kRolePermissionEditor, (context, page) => RolePermissionEditor(page: page));
}

/// Fallbacks when the page config does not send the lists (same values as RoleController).
const _defaultScopes = [
  ('all', '全部数据'),
  ('custom', '自定义部门'),
  ('dept_and_child', '本部门及以下'),
  ('dept', '本部门'),
  ('self', '仅本人'),
];
const _defaultFieldPerms = [('', '默认'), ('hidden', '隐藏'), ('masked', '脱敏'), ('readonly', '只读'), ('editable', '可编辑')];

/// 角色权限: menu / button permission tree (merged apps/*/menu.json), data scope (+ custom
/// department tree) and field permissions of one role. Saves with a partial
/// `PUT {save} {permissions, data_scope, field_perms}` — the basic fields (code, name, …) belong to
/// the generic form admin.system.role-form and are not sent. The server re-checks every grant
/// (40304: cannot grant more than you have; 422: unknown codes).
class RolePermissionEditor extends ConsumerStatefulWidget {
  const RolePermissionEditor({super.key, required this.page});

  final CustomPageContext page;

  @override
  ConsumerState<RolePermissionEditor> createState() => _RolePermissionEditorState();
}

class _RolePermissionEditorState extends ConsumerState<RolePermissionEditor> {
  String _scope = 'self';
  final Set<String> _perms = {};
  List<String> _stale = const [];
  final Set<int> _deptIds = {};
  final Map<String, String> _fieldPerms = {};
  List<(GridRow, int)> _menus = const [];
  List<(GridRow, int)> _depts = const [];
  List<GridRow> _fields = const [];
  Json _role = const {};
  bool _ready = false;
  bool _saving = false;
  String? _error;

  CustomPageContext get _page => widget.page;

  List<(String, String)> _options(String key, List<(String, String)> fallback) {
    final raw = _page.rawConfig[key];
    if (raw is! List || raw.isEmpty) return fallback;
    return [for (final o in asJsonList(raw)) ('${o['value'] ?? ''}', '${o['label'] ?? o['value'] ?? ''}')];
  }

  late final List<(String, String)> _scopes = _options('scopes', [for (final o in _defaultScopes) (o.$1, tr(o.$2))]);
  late final List<(String, String)> _fieldPermOptions = _options('fieldPerms', [for (final o in _defaultFieldPerms) (o.$1, tr(o.$2))]);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final load = _page.path('load');
    if (load == null) {
      setState(() => _error = tr('缺少角色 ID'));
      return;
    }
    final api = ref.read(renderApiProvider);
    try {
      final results = await Future.wait([
        api.get(load),
        api.get(_page.path('menus') ?? '/admin/api/system/menus'),
        api.get(_page.path('depts') ?? '/admin/api/system/depts'),
        api.get(_page.path('fields') ?? '/admin/api/system/fields'),
      ]);
      final r = asJson(results[0]);
      _role = r;
      // hidden page nodes (forms, custom pages) carry no permission code: not part of the grant tree
      _menus = [for (final e in flattenTree((results[1] as List?) ?? const [])) if (e.$1['type'] != 'page') e];
      _depts = flattenTree((results[2] as List?) ?? const []);
      _fields = asJsonList(results[3]);
      _perms.addAll(((r['permissions'] as List?) ?? const []).map((e) => '$e'));
      _stale = ((r['stale_permissions'] as List?) ?? const []).map((e) => '$e').toList();
      final ds = asJson(r['data_scope']);
      _scope = '${ds['scope'] ?? 'self'}';
      _deptIds.addAll(((ds['dept_ids'] as List?) ?? const []).map((e) => (e as num).toInt()));
      asJson(r['field_perms']).forEach((k, v) => _fieldPerms[k] = '$v');
      _ready = true;
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() {});
  }

  /// Body of the partial PUT (only the grants; the API leaves the basic fields untouched).
  Map<String, dynamic> get saveBody => {
        'permissions': _perms.toList()..sort(),
        'data_scope': {'scope': _scope, 'dept_ids': _scope == 'custom' ? (_deptIds.toList()..sort()) : <int>[]},
        'field_perms': {for (final e in _fieldPerms.entries) if (e.value.isNotEmpty) e.key: e.value},
      };

  Future<void> _save() async {
    final path = _page.path('save') ?? _page.path('load');
    if (path == null) return;
    setState(() => _saving = true);
    final ok = await runAction(context, () => ref.read(renderApiProvider).send('PUT', path, body: saveBody), success: tr('已保存'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) _page.close(true);
  }

  /// Checkbox tree; nodes whose [keyOf] is null (directories without a code) are headers only.
  Widget _checks<T>(String prefix, List<(GridRow, int)> nodes, Set<T> selected, T? Function(GridRow) keyOf, String Function(GridRow) label) => Container(
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: ShadTheme.of(context).colorScheme.muted,
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(8), children: [
          for (final (n, depth) in nodes)
            Padding(
              padding: EdgeInsets.only(left: depth * 18.0, top: 2, bottom: 2),
              child: Row(children: [
                if (keyOf(n) case final k?)
                  ShadCheckbox(
                    key: ValueKey('$prefix-$k'),
                    value: selected.contains(k),
                    onChanged: (v) => setState(() => v ? selected.add(k) : selected.remove(k)),
                  )
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(label(n), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          const SizedBox(height: 8),
          ShadButton.outline(onPressed: () => _page.close(false), child: Text(tr('关闭'))),
        ]),
      );
    }
    if (!_ready) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tr('角色：{name}（{code}）', {'name': _role['name'] ?? '', 'code': _role['code'] ?? ''}), key: const ValueKey('role-title'), style: t.textTheme.small),
      ),
      FormRow(
        tr('菜单/按钮'),
        _checks<String>('perm', _menus, _perms, (n) => n['perms'] as String?,
            (n) => n['perms'] != null ? '${n['name']}  ·  ${n['perms']}' : '${n['name']}'),
        hint: tr('来自各应用的 menu.json；只能授予自己拥有的权限；按钮需同时勾选所属菜单才会显示') +
            (_stale.isEmpty ? '' : tr('；已失效（菜单文件中已删除）：{list}', {'list': _stale.join(', ')})),
      ),
      FormRow(
        tr('数据范围'),
        OptionSelect<String>(key: const ValueKey('scope'), options: _scopes, value: _scope, onChanged: (v) => setState(() => _scope = v ?? 'self')),
      ),
      if (_scope == 'custom') FormRow(tr('部门'), _checks<int>('dept', _depts, _deptIds, (n) => (n['id'] as num).toInt(), (n) => '${n['name']}')),
      if (_fields.isNotEmpty)
        Padding(padding: EdgeInsets.only(top: 8, bottom: 4), child: Text(tr('字段权限'), style: t.textTheme.large)),
      for (final f in _fields)
        FormRow(
          '${f['label']}',
          OptionSelect<String>(
            key: ValueKey('fieldperm-${f['id']}'),
            options: _fieldPermOptions,
            value: _fieldPerms['${f['id']}'] ?? '',
            onChanged: (v) => setState(() => _fieldPerms['${f['id']}'] = v ?? ''),
          ),
          hint: tr('{resource}.{field}，默认：{perm}（多角色取最宽）', {'resource': f['resource'], 'field': f['field'], 'perm': f['default_perm']}),
        ),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        ShadButton.outline(onPressed: () => _page.close(false), child: Text(tr('取消'))),
        const SizedBox(width: 8),
        ShadButton(onPressed: _saving ? null : _save, child: Text(tr('保存'))),
      ]),
    ]);
    if (_page.mode != 'page') return SizedBox(width: 880, child: content);
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: _page.desc.title),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: content),
      ]),
    );
  }
}
