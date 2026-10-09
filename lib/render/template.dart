/// `{field}` placeholders (RENDER.md §5.1): replaced from the current row / record / route params.
/// No expressions are evaluated.
library;

import 'page_desc.dart';

final RegExp _ph = RegExp(r'\{([A-Za-z_][A-Za-z0-9_.]*)\}');

Object? lookup(Map<String, dynamic> data, String path) {
  Object? cur = data;
  for (final part in path.split('.')) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

String _str(Object? v) => switch (v) {
      null => '',
      List l => l.join(','),
      _ => '$v',
    };

/// Text (labels, confirm, messages): missing values become ''.
String fillText(String text, Map<String, dynamic> data) => text.replaceAllMapped(_ph, (m) => _str(lookup(data, m[1]!)));

/// API path / URL: values are URI-component encoded. Returns null when a placeholder is missing
/// (so `/admins/{id}` is never called as `/admins/`).
String? fillPath(String path, Map<String, dynamic> data) {
  var missing = false;
  final out = path.replaceAllMapped(_ph, (m) {
    final s = _str(lookup(data, m[1]!));
    if (s.isEmpty) missing = true;
    return Uri.encodeComponent(s);
  });
  return missing ? null : out;
}

/// Names used by placeholders in [text].
Set<String> placeholders(String text) => {for (final m in _ph.allMatches(text)) m[1]!};

/// Params / body: string values may be `{field}` templates; a value that is exactly one placeholder
/// keeps the original type (e.g. `{id}` → 3, not "3").
Object? fillValue(Object? v, Map<String, dynamic> data) {
  if (v is String) {
    final whole = _ph.matchAsPrefix(v);
    if (whole != null && whole.end == v.length) return lookup(data, whole[1]!);
    return fillText(v, data);
  }
  if (v is Map) return {for (final e in v.entries) '${e.key}': fillValue(e.value, data)};
  if (v is List) return [for (final e in v) fillValue(e, data)];
  return v;
}

Map<String, dynamic> fillParams(Object? params, Map<String, dynamic> data) =>
    params is Map ? {for (final e in params.entries) '${e.key}': fillValue(e.value, data)} : <String, dynamic>{};

/// `{field, eq}` | `{field, in}` | `{field, notEmpty}` (visibleWhen / hiddenWhen); unknown shapes → false.
bool matchCondition(Object? cond, Map<String, dynamic> data) {
  final c = asJson(cond);
  final field = c['field'];
  if (field is! String) return false;
  final v = lookup(data, field);
  if (c.containsKey('eq')) return sameValue(v, c['eq']);
  if (c['in'] is List) return (c['in'] as List).any((e) => sameValue(v, e));
  if (c['notEmpty'] == true) return !(v == null || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty));
  return false;
}

/// Row action / form action visibility (`visibleWhen` must match, `hiddenWhen` must not).
bool actionVisible(Map<String, dynamic> action, Map<String, dynamic> data) {
  if (action['visibleWhen'] != null && !matchCondition(action['visibleWhen'], data)) return false;
  if (action['hiddenWhen'] != null && matchCondition(action['hiddenWhen'], data)) return false;
  return true;
}

/// Tiny date formatter for column `format` (yyyy MM dd HH mm ss); unparsable values are shown as is.
String formatDateTime(Object? v, String? format) {
  if (v == null || v == '') return '';
  DateTime? d;
  if (v is num) {
    d = DateTime.fromMillisecondsSinceEpoch((v < 1e12 ? v * 1000 : v).toInt());
  } else {
    d = DateTime.tryParse('$v'.replaceFirst(' ', 'T'));
  }
  if (d == null) return '$v';
  String two(int n) => n.toString().padLeft(2, '0');
  return (format ?? 'yyyy-MM-dd HH:mm:ss')
      .replaceAll('yyyy', '${d.year}')
      .replaceAll('MM', two(d.month))
      .replaceAll('dd', two(d.day))
      .replaceAll('HH', two(d.hour))
      .replaceAll('mm', two(d.minute))
      .replaceAll('ss', two(d.second));
}
