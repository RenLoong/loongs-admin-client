import '../core/i18n.dart';

/// Current admin (GET /admin/api/auth/me).
class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.nickname,
    required this.isSuper,
    required this.permissions,
    required this.roles,
    required this.fields,
    this.deptName,
    this.dataScope,
  });

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] as num).toInt(),
        username: j['username'] as String,
        nickname: (j['nickname'] as String?) ?? j['username'] as String,
        isSuper: j['is_super'] == true,
        permissions: ((j['permissions'] as List?) ?? const []).map((e) => '$e').toSet(),
        roles: ((j['roles'] as List?) ?? const [])
            .map((e) => (e as Map)['name']?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(),
        fields: _flattenFields(j['fields']),
        deptName: (j['dept'] as Map?)?['name'] as String?,
        dataScope: _describeScope(j['data_scope']),
      );

  final int id;
  final String username;
  final String nickname;
  final bool isSuper;
  final Set<String> permissions;
  final List<String> roles;

  /// "resource.field" → hidden|masked|readonly|editable (empty for super admin).
  final Map<String, String> fields;
  final String? deptName;
  final String? dataScope;

  /// `{admin: {mobile: masked}}` → `{admin.mobile: masked}`.
  static Map<String, String> _flattenFields(Object? f) {
    final out = <String, String>{};
    if (f is Map) {
      f.forEach((res, fields) {
        if (fields is Map) {
          fields.forEach((k, v) => out['$res.$k'] = '$v');
        } else {
          out['$res'] = '$fields';
        }
      });
    }
    return out;
  }

  static String? _describeScope(Object? d) {
    if (d is! Map) return null;
    if (d['all'] == true) return tr('全部数据');
    final n = (d['dept_ids'] as List?)?.length ?? 0;
    final parts = [if (n > 0) tr('{n} 个部门', {'n': n}), if (d['self'] == true) tr('本人')];
    return parts.isEmpty ? tr('无') : parts.join(' + ');
  }

  bool can(String code) => isSuper || permissions.contains('*') || permissions.contains(code);
}

/// Sidebar node (GET /admin/api/auth/menus): dir or menu, buttons are not included. Menus come
/// from the server's apps/*/menu.json files; [key] is stable (perms code or path), not a DB id.
class MenuNode {
  const MenuNode({
    required this.key,
    required this.type,
    required this.name,
    this.path,
    this.icon,
    this.perms,
    this.page,
    this.pageType,
    this.children = const [],
  });

  factory MenuNode.fromJson(Map<String, dynamic> j) => MenuNode(
        key: '${j['key'] ?? j['perms'] ?? j['path'] ?? j['name']}',
        type: '${j['type']}',
        name: '${j['name']}',
        path: j['path'] as String?,
        icon: j['icon'] as String?,
        perms: j['perms'] as String?,
        page: j['page'] as String?,
        pageType: j['page_type'] as String?,
        children: ((j['children'] as List?) ?? const [])
            .map((e) => MenuNode.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  final String key;
  final String type;
  final String name;
  final String? path;
  final String? icon;
  final String? perms;

  /// Generic page (loongs/render) declared in menu.json: page code + page_type
  /// (dashboard | form | table | detail | custom). Null for hand-written pages.
  final String? page;
  final String? pageType;
  final List<MenuNode> children;

  bool get isDir => type == 'dir';

  /// Depth-first search for the menu whose [path] equals [p].
  static MenuNode? findByPath(List<MenuNode> nodes, String p) {
    for (final n in nodes) {
      if (n.path == p) return n;
      final c = findByPath(n.children, p);
      if (c != null) return c;
    }
    return null;
  }
}
