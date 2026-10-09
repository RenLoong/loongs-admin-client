/// Renderer-neutral chart description of loongs/render (RENDER.md §6.1.1) → a typed model plus the
/// pure computations the fl_chart translation needs (rows, categories, nice axis ranges, dual-axis
/// mapping). No Flutter widgets here, so it is unit-testable.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import '../page_desc.dart';
import '../template.dart';
import 'chart_format.dart';
import '../../core/i18n.dart';

/// Chart types this client draws with fl_chart; `custom` goes through [customChartRegistry].
const Set<String> kChartTypes = {'line', 'bar', 'stackedBar', 'area', 'pie', 'donut', 'radar', 'scatter', 'gauge', 'combo'};

const List<String> kDefaultPalette = ['#2563eb', '#f59e0b', '#10b981', '#ef4444', '#8b5cf6', '#06b6d4', '#ec4899', '#84cc16'];

/// The same categorical palette brightened for dark backgrounds (chart1 … chart8 in dark mode).
const List<String> kDefaultPaletteDark = ['#60a5fa', '#fbbf24', '#34d399', '#f87171', '#a78bfa', '#22d3ee', '#f472b6', '#a3e635'];

const Map<String, Color> _lightTokens = {
  'primary': Color(0xFF2563EB), 'secondary': Color(0xFF64748B), 'success': Color(0xFF16A34A), 'warning': Color(0xFFD97706),
  'danger': Color(0xFFDC2626), 'info': Color(0xFF0EA5E9), 'muted': Color(0xFF94A3B8), 'default': Color(0xFF64748B),
};

const Map<String, Color> _darkTokens = {
  'primary': Color(0xFF60A5FA), 'secondary': Color(0xFF94A3B8), 'success': Color(0xFF4ADE80), 'warning': Color(0xFFFBBF24),
  'danger': Color(0xFFF87171), 'info': Color(0xFF38BDF8), 'muted': Color(0xFF64748B), 'default': Color(0xFF94A3B8),
};

/// `#rgb` / `#rrggbb` / `#rrggbbaa` (CSS order), a theme token (primary … default, chart1 … chart8)
/// or a `"light|dark"` pair (render's Color::pair) → Color for the current theme; null when unknown.
Color? parseColor(Object? c, {bool dark = false}) {
  if (c is! String) return null;
  final bar = c.indexOf('|');
  if (bar > 0) return parseColor(dark ? c.substring(bar + 1) : c.substring(0, bar), dark: dark);
  final tokens = dark ? _darkTokens : _lightTokens;
  if (tokens.containsKey(c)) return tokens[c];
  final chart = RegExp(r'^chart([1-8])$').firstMatch(c);
  if (chart != null) return parseColor((dark ? kDefaultPaletteDark : kDefaultPalette)[int.parse(chart[1]!) - 1]);
  final m = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(c);
  if (m == null) return null;
  var h = m[1]!;
  if (h.length == 3) h = h.split('').map((x) => '$x$x').join();
  if (h.length == 6) h = '${h}ff';
  final rgba = int.parse(h, radix: 16);
  return Color(((rgba & 0xff) << 24) | (rgba >> 8));
}

double? toDouble(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : (v is bool ? (v ? 1 : 0) : null));

/// Chart API payload → rows: a list, `{list|rows|items: [...]}` or a single object (gauge / stat).
List<Json> chartRows(Object? data) {
  if (data is List) return asJsonList(data);
  if (data is Map) {
    for (final k in const ['list', 'rows', 'items']) {
      if (data[k] is List) return asJsonList(data[k]);
    }
    return [data.cast<String, dynamic>()];
  }
  return const [];
}

class ChartSeries {
  ChartSeries(Json j, {bool dark = false})
      : field = '${j['field']}',
        name = '${j['name'] ?? j['field']}',
        type = j['type'] as String?,
        color = parseColor(j['color'], dark: dark),
        area = j['area'] == true,
        smooth = j['smooth'] == true,
        dashed = j['dashed'] == true,
        right = j['axis'] == 'right',
        stack = j['stack'] as String?,
        labels = j['labels'] as bool?,
        format = j['format'] as String?;

  final String field;
  final String name;
  final String? type;
  final Color? color;
  final bool area;
  final bool smooth;
  final bool dashed;
  final bool right;
  final String? stack;
  final bool? labels;
  final String? format;
}

class ChartAxis {
  ChartAxis(Json j)
      : min = toDouble(j['min']),
        max = toDouble(j['max']),
        format = j['format'] as String?,
        name = j['name'] as String?;

  final double? min;
  final double? max;
  final String? format;
  final String? name;

  String label(double v) => format != null ? formatTemplate(format!, {'value': _clean(v)}) : compactNumber(_clean(v));
}

num _clean(double v) => v == v.roundToDouble() ? v.round() : double.parse(v.toStringAsFixed(4));

class ChartMark {
  ChartMark(Json j, {bool dark = false})
      : value = j['value'],
        from = j['from'],
        to = j['to'],
        label = j['label'] as String?,
        axis = '${j['axis'] ?? (j.containsKey('from') ? 'x' : 'left')}',
        color = parseColor(j['color'], dark: dark),
        dashed = j['dashed'] != false;

  final Object? value;
  final Object? from;
  final Object? to;
  final String? label;
  final String axis;
  final Color? color;
  final bool dashed;
}

/// One chart block description. [dark] picks the dark variants of tokens / pairs / the palette.
class ChartSpec {
  ChartSpec(this.raw, {this.dark = false})
      : type = '${raw['chart'] ?? ''}',
        title = raw['title'] as String?,
        x = raw['x'] is Map ? asJson(raw['x']) : null,
        series = [for (final s in asJsonList(raw['series'])) ChartSeries(s, dark: dark)],
        left = ChartAxis(asJson(asJson(raw['yAxis'])['left'])),
        right = ChartAxis(asJson(asJson(raw['yAxis'])['right'])),
        legend = raw['legend'] as String?,
        tooltip = asJson(raw['tooltip']),
        labels = asJson(raw['labels']),
        markLines = [for (final m in asJsonList(raw['markLines'])) ChartMark(m, dark: dark)],
        markAreas = [for (final m in asJsonList(raw['markAreas'])) ChartMark(m, dark: dark)],
        palette = [for (final c in (raw['palette'] is List ? raw['palette'] as List : (dark ? kDefaultPaletteDark : kDefaultPalette))) parseColor(c, dark: dark) ?? const Color(0xFF2563EB)],
        height = ((raw['height'] as num?) ?? 300).toDouble(),
        emptyText = '${raw['emptyText'] ?? tr('暂无数据')}',
        fl = asJson(asJson(raw['renderer'])['fl_chart']);

  final Json raw;
  final bool dark;
  final String type;
  final String? title;
  final Json? x;
  final List<ChartSeries> series;
  final ChartAxis left;
  final ChartAxis right;
  final String? legend;
  final Json tooltip;
  final Json labels;
  final List<ChartMark> markLines;
  final List<ChartMark> markAreas;
  final List<Color> palette;
  final double height;
  final String emptyText;

  /// `renderer.fl_chart` passthrough (whitelisted by loongs/render; unknown keys are ignored here).
  final Json fl;

  String? get customName => raw['name'] as String?;
  Json get customConfig => asJson(raw['config']);
  String? get api => raw['api'] as String?;

  String get xField => '${x?['field'] ?? ''}';
  String get xType => '${x?['type'] ?? 'category'}';
  bool get xNumeric => xType == 'value' || type == 'scatter' && xType != 'category' && xType != 'time';
  bool get hasRight => series.any((s) => s.right);
  bool get showLabels => labels['show'] == true;

  Color colorOf(int i) => series.length > i && series[i].color != null ? series[i].color! : palette[i % palette.length];

  double? flNum(String key) => toDouble(fl[key]);
  bool? flBool(String key) => fl[key] is bool ? fl[key] as bool : null;

  /// x axis label of a raw x value (date pattern for time axes, {value} template otherwise).
  String xLabel(Object? v) {
    final f = x?['format'] as String?;
    if (xType == 'time') return formatDate(v, f ?? 'MM-dd');
    if (f != null) return formatTemplate(f, {'value': v});
    return v is num ? plainNumber(v) : '${v ?? ''}';
  }

  /// Text of a series value: the series `format` template, else a plain number.
  String valueText(ChartSeries s, Object? raw, {Object? xValue, num? percent}) {
    final vars = <String, Object?>{'value': raw, 'series': s.name, 'x': xValue == null ? null : xLabel(xValue), 'name': xValue, 'percent': percent};
    if (s.format != null) return formatTemplate(s.format!, vars);
    final n = toDouble(raw);
    return n == null ? '${raw ?? ''}' : plainNumber(n);
  }

  /// Tooltip line: `tooltip.format` (with {value} {series} {x} …) or "series: value".
  String tooltipText(ChartSeries s, Object? raw, Object? xValue, {num? percent}) {
    final f = tooltip['format'] as String?;
    if (f == null) return '${s.name}: ${valueText(s, raw, xValue: xValue, percent: percent)}';
    return formatTemplate(f, {'value': raw, 'series': s.name, 'x': xValue == null ? null : xLabel(xValue), 'name': xValue, 'percent': percent});
  }

  /// Data label (bars, slices): `labels.format`, else the series format / plain value.
  String labelText(ChartSeries s, Object? raw, Object? xValue, {num? percent}) {
    final f = labels['format'] as String?;
    if (f == null) return valueText(s, raw, xValue: xValue, percent: percent);
    return formatTemplate(f, {'value': raw, 'series': s.name, 'x': xValue == null ? null : xLabel(xValue), 'name': xValue, 'percent': percent});
  }
}

/// Inclusive numeric range with a "nice" tick interval.
class AxisRange {
  const AxisRange(this.min, this.max, this.interval);

  final double min;
  final double max;
  final double interval;

  double get span => max - min;

  /// Maps [v] from this range into [target] (dual axis: right values drawn on the left scale).
  double mapTo(AxisRange target, double v) => target.min + (v - min) / (span == 0 ? 1 : span) * target.span;

  @override
  String toString() => 'AxisRange($min, $max, step $interval)';
}

double _niceStep(double raw) {
  if (raw <= 0 || raw.isNaN) return 1;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final f = raw / exp;
  final nice = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return nice * exp;
}

/// Range covering [values] (and 0 when all are positive) honouring explicit [min] / [max];
/// about [ticks] intervals.
AxisRange niceRange(Iterable<double> values, {double? min, double? max, int ticks = 5}) {
  final vs = values.where((v) => v.isFinite).toList();
  var lo = min ?? (vs.isEmpty ? 0 : math.min(0, vs.reduce(math.min)));
  var hi = max ?? (vs.isEmpty ? 1 : vs.reduce(math.max));
  if (hi <= lo) hi = lo + (lo.abs() > 0 ? lo.abs() : 1);
  var step = _niceStep((hi - lo) / ticks);
  // Counts (all whole numbers) never get fractional ticks: 0..1 → 0, 1 instead of 0, 0.2 … 1.
  if (step < 1 && vs.isNotEmpty && vs.every((v) => v == v.roundToDouble()) && (min == null || max == null)) step = 1;
  if (max == null) hi = (hi / step).ceil() * step;
  if (min == null) lo = (lo / step).floor() * step;
  final interval = (min != null && max != null) ? (hi - lo) / ticks : step;
  return AxisRange(lo, hi, interval);
}

/// Cartesian data prepared for fl_chart: x positions (category index or numeric x), per-series y
/// values on the LEFT scale (right-axis series mapped), raw values for tooltips.
class CartesianModel {
  CartesianModel._(this.spec, this.rows, this.xs, this.raw, this.y, this.left, this.right);

  factory CartesianModel.build(ChartSpec spec, List<Json> rows) {
    final xs = <double>[
      for (var i = 0; i < rows.length; i++) spec.xNumeric ? (toDouble(lookup(rows[i], spec.xField)) ?? i.toDouble()) : i.toDouble(),
    ];
    final raw = <List<double?>>[
      for (final s in spec.series) [for (final r in rows) toDouble(lookup(r, s.field))],
    ];
    final stacked = spec.type == 'stackedBar';
    Iterable<double> valuesOf(bool right) sync* {
      if (stacked && !right) {
        final groups = <String, List<int>>{};
        for (var i = 0; i < spec.series.length; i++) {
          groups.putIfAbsent(spec.series[i].stack ?? '_', () => []).add(i);
        }
        for (var r = 0; r < rows.length; r++) {
          for (final g in groups.values) {
            yield g.fold<double>(0, (sum, i) => sum + math.max(0, raw[i][r] ?? 0));
          }
        }
        return;
      }
      for (var i = 0; i < spec.series.length; i++) {
        if (spec.series[i].right != right) continue;
        for (final v in raw[i]) {
          if (v != null) yield v;
        }
      }
      for (final m in spec.markLines) {
        final v = toDouble(m.value);
        if (v != null && (m.axis == 'right') == right && m.axis != 'x') yield v;
      }
    }

    final left = niceRange(valuesOf(false), min: spec.left.min, max: spec.left.max, ticks: 5);
    final right = spec.hasRight ? niceRange(valuesOf(true), min: spec.right.min, max: spec.right.max) : null;
    final y = <List<double?>>[
      for (var i = 0; i < spec.series.length; i++)
        [for (final v in raw[i]) v == null ? null : (spec.series[i].right && right != null ? right.mapTo(left, v) : v)],
    ];
    return CartesianModel._(spec, rows, xs, raw, y, left, right);
  }

  final ChartSpec spec;
  final List<Json> rows;
  final List<double> xs;
  final List<List<double?>> raw;
  final List<List<double?>> y;
  final AxisRange left;
  final AxisRange? right;

  bool get isEmpty => rows.isEmpty || raw.every((s) => s.every((v) => v == null));

  Object? xValue(int i) => i >= 0 && i < rows.length ? lookup(rows[i], spec.xField) : null;

  /// Position of an x value used by marks: category index (by raw or label match) or the number.
  double? xPosition(Object? v) {
    if (spec.xNumeric) return toDouble(v);
    for (var i = 0; i < rows.length; i++) {
      final xv = xValue(i);
      if (sameValue(xv, v) || spec.xLabel(xv) == '$v') return i.toDouble();
    }
    return null;
  }

  /// y on the left scale for a mark on [axis].
  double? markY(ChartMark m, Object? v) {
    final d = toDouble(v);
    if (d == null) return null;
    return m.axis == 'right' && right != null ? right!.mapTo(left, d) : d;
  }

  /// Right-axis label at left-scale position [leftY].
  String rightLabel(double leftY) => right == null ? '' : spec.right.label(left.mapTo(right!, leftY));
}
