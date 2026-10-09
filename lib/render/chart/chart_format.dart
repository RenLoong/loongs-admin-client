/// Format templates of loongs/render (RENDER.md §6.1.1): placeholders `{value}` `{series}` `{x}`
/// `{name}` `{percent}` (or any field path) with filters `|thousands` `|percent:N` `|fixed:N`
/// `|money:CNY` `|date:MM-dd`; `{{` / `}}` are literal braces. Never evaluates code.
library;

import '../../core/i18n.dart';
import '../template.dart';

final RegExp _token = RegExp(r'\{\{|\}\}|\{([A-Za-z_][A-Za-z0-9_.]*)(?:\|([a-z]+)(?::([^{}]*))?)?\}');

/// Fills [template] from [vars]; missing values become ''.
String formatTemplate(String template, Map<String, Object?> vars) => template.replaceAllMapped(_token, (m) {
      if (m[0] == '{{') return '{';
      if (m[0] == '}}') return '}';
      final name = m[1]!;
      final v = vars.containsKey(name) ? vars[name] : lookup(vars.cast<String, dynamic>(), name);
      return applyFilter(v, m[2], m[3]);
    });

/// One value through an optional filter. Unknown filters leave the value as is.
String applyFilter(Object? v, String? filter, [String? arg]) {
  if (v == null) return '';
  final n = v is num ? v : num.tryParse('$v');
  switch (filter) {
    case null || '':
      return n != null && v is! String ? plainNumber(n) : '$v';
    case 'thousands':
      return n == null ? '$v' : thousands(n);
    case 'percent':
      return n == null ? '$v' : '${(n * 100).toStringAsFixed(int.tryParse(arg ?? '') ?? 0)}%';
    case 'fixed':
      return n == null ? '$v' : n.toStringAsFixed(int.tryParse(arg ?? '') ?? 0);
    case 'money':
      if (n == null) return '$v';
      final cur = (arg == null || arg.isEmpty) ? 'CNY' : arg;
      final digits = cur == 'JPY' || cur == 'KRW' ? 0 : 2;
      final sym = const {'CNY': '¥', 'USD': r'$', 'EUR': '€', 'GBP': '£', 'JPY': '¥', 'HKD': r'HK$', 'KRW': '₩'}[cur] ?? '$cur ';
      return '${n < 0 ? '-' : ''}$sym${thousands(n.abs(), digits: digits)}';
    case 'date':
      return formatDate(v, arg);
  }
  return '$v';
}

/// 12 → "12", 12.5 → "12.5", 0.12345 → "0.12" (at most 2 decimals, trailing zeros trimmed).
String plainNumber(num n) {
  if (n is int || n == n.roundToDouble()) return n.round().toString();
  var s = n.toStringAsFixed(2);
  while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 1234567.891 → "1,234,567.89"; [digits] fixes the decimals (else like [plainNumber]).
String thousands(num n, {int? digits}) {
  final s = digits != null ? n.abs().toStringAsFixed(digits) : plainNumber(n.abs());
  final parts = s.split('.');
  final int0 = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < int0.length; i++) {
    if (i > 0 && (int0.length - i) % 3 == 0) buf.write(',');
    buf.write(int0[i]);
  }
  return '${n < 0 ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

/// Date filter: accepts DateTime-parsable strings, "yyyy-MM" months and epoch seconds / millis.
String formatDate(Object? v, String? pattern) {
  if (v is String && RegExp(r'^\d{4}-\d{2}$').hasMatch(v)) v = '$v-01';
  final out = formatDateTime(v, pattern ?? 'yyyy-MM-dd');
  return out;
}

/// Compact axis label: 12000 → "1.2万", 3500000 → "350万", 120000000 → "1.2亿".
/// English (any language but zh): 12000 → "12K", 3500000 → "3.5M", 1.2e9 → "1.2B".
String compactNumber(num n) {
  final a = n.abs();
  if (!currentLanguage.startsWith('zh')) {
    String f(double d, String u) => '${plainNumber(double.parse(d.toStringAsFixed(1)))}$u';
    if (a >= 1e9) return f(n / 1e9, 'B');
    if (a >= 1e6) return f(n / 1e6, 'M');
    if (a >= 1e3) return f(n / 1e3, 'K');
    return plainNumber(n is double ? double.parse(n.toStringAsFixed(2)) : n);
  }
  if (a >= 1e8) return '${plainNumber(double.parse((n / 1e8).toStringAsFixed(1)))}亿';
  if (a >= 1e4) return '${plainNumber(double.parse((n / 1e4).toStringAsFixed(1)))}万';
  return plainNumber(n is double ? double.parse(n.toStringAsFixed(2)) : n);
}
