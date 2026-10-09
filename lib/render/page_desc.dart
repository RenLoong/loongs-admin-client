/// Page description of loongs/render (RENDER.md §5): `{schema, page, type, title, version, breadcrumb, body, meta}`.
library;

/// Highest description schema this client can render (sent as `X-Render-Schema`).
const int kRenderSchema = 1;

/// Page types this client renders (custom pages: registered components, see custom_page.dart;
/// unregistered ones degrade to a placeholder, RENDER.md §7 / §9).
const Set<String> kRenderedPageTypes = {'table', 'form', 'dashboard', 'detail', 'custom'};

typedef Json = Map<String, dynamic>;

Json asJson(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Json> asJsonList(Object? v) => v is List ? [for (final e in v) if (e is Map) e.cast<String, dynamic>()] : const [];

class PageDesc {
  PageDesc(this.raw);

  final Json raw;

  int get schema => (raw['schema'] as num?)?.toInt() ?? 0;
  String get page => '${raw['page'] ?? ''}';
  String get type => '${raw['type'] ?? ''}';
  String get title => '${raw['title'] ?? ''}';
  String get version => '${raw['version'] ?? ''}';
  List<String> get breadcrumb => [for (final b in (raw['breadcrumb'] as List?) ?? const []) '$b'];
  Json get body => asJson(raw['body']);
  Json get meta => asJson(raw['meta']);
}

/// One option of select / radio / checkbox / tag columns (`{value, label, color, children}`).
class OptionItem {
  const OptionItem(this.value, this.label, {this.color, this.depth = 0});

  final Object? value;
  final String label;
  final String? color;
  final int depth;

  /// Accepts render options (`value/label`) and plain API rows (`id/name`, `title`); trees are flattened.
  static List<OptionItem> listFrom(Object? raw, [int depth = 0]) => [
        for (final o in asJsonList(raw)) ...[
          OptionItem(o['value'] ?? o['id'], '${o['label'] ?? o['name'] ?? o['title'] ?? o['value'] ?? o['id']}',
              color: o['color'] as String?, depth: depth),
          ...listFrom(o['children'], depth + 1),
        ],
      ];
}

/// Loose equality for option values coming from JSON (1 == "1", true == 1).
bool sameValue(Object? a, Object? b) {
  if (a == b) return true;
  if (a == null || b == null) return false;
  if (a is bool || b is bool) return _truthy(a) == _truthy(b);
  return '$a' == '$b';
}

bool _truthy(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
