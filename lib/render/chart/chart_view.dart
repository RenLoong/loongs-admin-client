import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../components/unknown.dart';
import '../page_desc.dart';
import '../template.dart';
import 'chart_spec.dart';
import '../../core/i18n.dart';

/// Client-registered chart components for `Chart::custom(name, config)` (RENDER.md §6.1.1). A name
/// that is not registered degrades to [UnknownComponent] (§7). Register at startup:
///   customChartRegistry['heatmap'] = (context, spec, rows) => MyHeatmap(...);
typedef CustomChartBuilder = Widget Function(BuildContext context, ChartSpec spec, List<Json> rows);

final Map<String, CustomChartBuilder> customChartRegistry = {};

/// Draws one chart description with [rows] (already loaded) using fl_chart:
/// line / area / bar / stackedBar / combo (bar + line layers) / scatter / pie / donut / radar /
/// gauge (half donut). Type, series, axes (dual axis), colors, formats, marks, legend, height and
/// the whitelisted `renderer.fl_chart` options come from the backend; nothing is hard-coded per page.
class RenderChart extends StatelessWidget {
  const RenderChart({super.key, required this.spec, required this.rows});

  final ChartSpec spec;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (spec.type == 'custom') {
      final b = customChartRegistry[spec.customName ?? ''];
      return SizedBox(
        height: spec.height,
        child: b != null ? b(context, spec, rows) : Center(child: UnknownComponent(tr('图表'), spec.customName ?? 'custom')),
      );
    }
    if (!kChartTypes.contains(spec.type)) {
      return SizedBox(height: math.min(spec.height, 120), child: Center(child: UnknownComponent(tr('图表'), spec.type)));
    }
    final empty = rows.isEmpty || spec.series.isEmpty || rows.every((r) => spec.series.every((s) => toDouble(lookup(r, s.field)) == null));
    if (empty) {
      return SizedBox(height: spec.height, child: Center(child: Text(spec.emptyText, style: t.textTheme.muted)));
    }
    final chart = switch (spec.type) {
      'pie' || 'donut' => _pie(context),
      'gauge' => _gauge(context),
      'radar' => _radar(context),
      _ => _cartesian(context),
    };
    final legend = _legend(context);
    final pos = spec.legend ?? (legend == null ? 'none' : (spec.type == 'pie' || spec.type == 'donut' ? 'bottom' : 'top'));
    final caption = _areaCaption(context);
    Widget body = SizedBox(height: spec.height, child: chart);
    if (legend != null && pos != 'none') {
      body = switch (pos) {
        'left' => Row(children: [legend, const SizedBox(width: 8), Expanded(child: body)]),
        'right' => Row(children: [Expanded(child: body), const SizedBox(width: 8), legend]),
        'bottom' => Column(mainAxisSize: MainAxisSize.min, children: [body, const SizedBox(height: 8), legend]),
        _ => Column(mainAxisSize: MainAxisSize.min, children: [legend, const SizedBox(height: 8), body]),
      };
    }
    return caption == null ? body : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [body, caption]);
  }

  Duration get _anim => Duration(milliseconds: (spec.flNum('animationMs') ?? 250).round());

  TextStyle _small(BuildContext context) => TextStyle(fontSize: 11, color: ShadTheme.of(context).colorScheme.mutedForeground);

  // ------------------------------------------------------------------ legend / captions

  Widget? _legend(BuildContext context) {
    final items = <(Color, String)>[];
    if (spec.type == 'pie' || spec.type == 'donut') {
      for (var i = 0; i < rows.length; i++) {
        items.add((spec.palette[i % spec.palette.length], spec.xLabel(lookup(rows[i], spec.xField))));
      }
    } else if (spec.type != 'gauge' && spec.series.length > 1) {
      for (var i = 0; i < spec.series.length; i++) {
        items.add((spec.colorOf(i), spec.series[i].name));
      }
    }
    if (items.isEmpty) return null;
    final vertical = spec.legend == 'left' || spec.legend == 'right';
    final children = [
      for (final (c, name) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(name, style: const TextStyle(fontSize: 12)),
        ]),
    ];
    return vertical
        ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in children) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: c),
          ])
        : Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 4, children: children);
  }

  Widget? _areaCaption(BuildContext context) {
    final labelled = spec.markAreas.where((m) => m.label != null).toList();
    if (labelled.isEmpty || !_isCartesian) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 12, children: [
        for (final m in labelled)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 14, height: 8, color: m.color ?? const Color(0x33F59E0B)),
            const SizedBox(width: 4),
            Text('${m.label}（${m.from} ~ ${m.to}）', style: _small(context)),
          ]),
      ]),
    );
  }

  bool get _isCartesian => !{'pie', 'donut', 'gauge', 'radar'}.contains(spec.type);

  // ------------------------------------------------------------------ cartesian

  Widget _cartesian(BuildContext context) {
    final m = CartesianModel.build(spec, rows);
    return LayoutBuilder(builder: (context, box) {
      final titles = _titles(context, m, box.maxWidth);
      final grid = FlGridData(
        drawHorizontalLine: spec.flBool('gridHorizontal') ?? true,
        drawVerticalLine: spec.flBool('gridVertical') ?? false,
        horizontalInterval: _leftInterval(m),
        getDrawingHorizontalLine: (_) => FlLine(color: ShadTheme.of(context).colorScheme.border, strokeWidth: 0.6),
        getDrawingVerticalLine: (_) => FlLine(color: ShadTheme.of(context).colorScheme.border, strokeWidth: 0.6),
      );
      final border = FlBorderData(
        show: spec.flBool('borderVisible') ?? false,
        border: Border.all(color: ShadTheme.of(context).colorScheme.border),
      );
      final extra = _extraLines(context, m);
      final ranges = _ranges(m);
      switch (spec.type) {
        case 'bar' || 'stackedBar':
          return BarChart(_barData(context, m, titles, grid, border, extra, ranges, spec.series.indexed.map((e) => e.$1).toList()), duration: _anim);
        case 'combo':
          final bars = [for (var i = 0; i < spec.series.length; i++) if (spec.series[i].type == 'bar') i];
          final lines = [for (var i = 0; i < spec.series.length; i++) if (spec.series[i].type != 'bar') i];
          final hidden = _hiddenTitles(titles);
          return Stack(children: [
            Positioned.fill(child: BarChart(_barData(context, m, titles, grid, border, extra, ranges, bars), duration: _anim)),
            if (lines.isNotEmpty)
              Positioned.fill(
                child: LineChart(
                  _lineData(context, m, hidden, const FlGridData(show: false), FlBorderData(show: false), const ExtraLinesData(), const RangeAnnotations(), lines,
                      category: true),
                  duration: _anim,
                ),
              ),
          ]);
        case 'scatter':
          return ScatterChart(_scatterData(context, m, titles, grid, border), duration: _anim);
        default:
          return LineChart(_lineData(context, m, titles, grid, border, extra, ranges, [for (var i = 0; i < spec.series.length; i++) i]), duration: _anim);
      }
    });
  }

  double _leftInterval(CartesianModel m) => spec.flNum('interval') ?? m.left.interval;

  FlTitlesData _titles(BuildContext context, CartesianModel m, double width) {
    final style = _small(context);
    final n = m.rows.length;
    // Thin category labels so they never overlap: estimated label width × count vs plot width.
    final longest = [for (var i = 0; i < n; i++) spec.xLabel(m.xValue(i)).length].fold<int>(1, math.max);
    final plot = math.max(1.0, width - 48 - (m.right != null ? 48 : 0));
    final every = math.max(1, (n * (longest * 7.5 + 16) / plot).ceil());
    Widget axisName(String? name) => name == null ? const SizedBox.shrink() : Text(name, style: style);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        axisNameWidget: spec.left.name == null ? null : axisName(spec.left.name),
        axisNameSize: spec.left.name == null ? 0 : 16,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          interval: _leftInterval(m),
          getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(spec.left.label(v), style: style)),
        ),
      ),
      rightTitles: AxisTitles(
        axisNameWidget: m.right != null && spec.right.name != null ? axisName(spec.right.name) : null,
        axisNameSize: m.right != null && spec.right.name != null ? 16 : 0,
        sideTitles: SideTitles(
          showTitles: m.right != null,
          reservedSize: m.right != null ? 48 : 0,
          interval: _leftInterval(m),
          getTitlesWidget: (v, meta) => SideTitleWidget(meta: meta, child: Text(m.rightLabel(v), style: style)),
        ),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: spec.x?['name'] is String ? axisName(spec.x!['name'] as String) : null,
        axisNameSize: spec.x?['name'] is String ? 16 : 0,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: spec.xNumeric ? null : 1,
          getTitlesWidget: (v, meta) {
            if (spec.xNumeric) return SideTitleWidget(meta: meta, child: Text(spec.xLabel(_num(v)), style: style));
            final i = v.round();
            if ((v - i).abs() > 0.01 || i < 0 || i >= n || i % every != 0) return const SizedBox.shrink();
            return SideTitleWidget(meta: meta, child: Text(spec.xLabel(m.xValue(i)), style: style));
          },
        ),
      ),
    );
  }

  /// Same reserved space as [t] but nothing drawn (the line layer of combo charts).
  FlTitlesData _hiddenTitles(FlTitlesData t) {
    AxisTitles hide(AxisTitles a) => AxisTitles(
          axisNameWidget: a.axisNameWidget == null ? null : const SizedBox.shrink(),
          axisNameSize: a.axisNameSize,
          sideTitles: SideTitles(
            showTitles: a.sideTitles.showTitles,
            reservedSize: a.sideTitles.reservedSize,
            getTitlesWidget: (_, _) => const SizedBox.shrink(),
          ),
        );
    return FlTitlesData(leftTitles: hide(t.leftTitles), rightTitles: hide(t.rightTitles), bottomTitles: hide(t.bottomTitles), topTitles: hide(t.topTitles));
  }

  ExtraLinesData _extraLines(BuildContext context, CartesianModel m) {
    final h = <HorizontalLine>[];
    final v = <VerticalLine>[];
    for (final mk in spec.markLines) {
      final color = mk.color ?? const Color(0xFFEF4444);
      final dash = mk.dashed ? const [6, 4] : null;
      if (mk.axis == 'x') {
        final x = m.xPosition(mk.value);
        if (x == null) continue;
        v.add(VerticalLine(
          x: x,
          color: color,
          strokeWidth: 1,
          dashArray: dash,
          label: VerticalLineLabel(show: mk.label != null, labelResolver: (_) => mk.label ?? '', style: TextStyle(fontSize: 11, color: color)),
        ));
      } else {
        final y = m.markY(mk, mk.value);
        if (y == null) continue;
        h.add(HorizontalLine(
          y: y,
          color: color,
          strokeWidth: 1,
          dashArray: dash,
          label: HorizontalLineLabel(
            show: mk.label != null,
            alignment: Alignment.topRight,
            labelResolver: (_) => mk.label ?? '',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ));
      }
    }
    return ExtraLinesData(horizontalLines: h, verticalLines: v);
  }

  RangeAnnotations _ranges(CartesianModel m) {
    final h = <HorizontalRangeAnnotation>[];
    final v = <VerticalRangeAnnotation>[];
    for (final a in spec.markAreas) {
      final color = a.color ?? const Color(0x33F59E0B);
      if (a.axis == 'x') {
        final x1 = m.xPosition(a.from), x2 = m.xPosition(a.to);
        if (x1 == null || x2 == null) continue;
        // Category axes: cover the whole slot of both ends, clamped to the plotted range.
        final pad = spec.xNumeric ? 0.0 : 0.5;
        final hiX = spec.xNumeric ? double.infinity : math.max(0, m.rows.length - 1).toDouble();
        final loX = spec.xNumeric ? double.negativeInfinity : 0.0;
        v.add(VerticalRangeAnnotation(
          x1: math.max(loX, math.min(x1, x2) - pad),
          x2: math.min(hiX, math.max(x1, x2) + pad),
          color: color,
        ));
      } else {
        final y1 = m.markY(a, a.from), y2 = m.markY(a, a.to);
        if (y1 == null || y2 == null) continue;
        h.add(HorizontalRangeAnnotation(y1: math.min(y1, y2), y2: math.max(y1, y2), color: color));
      }
    }
    return RangeAnnotations(horizontalRangeAnnotations: h, verticalRangeAnnotations: v);
  }

  Color _tooltipBg(BuildContext context) => ShadTheme.of(context).colorScheme.foreground.withValues(alpha: 0.88);

  TextStyle _tooltipStyle(BuildContext context, Color c) =>
      TextStyle(color: ShadTheme.of(context).colorScheme.background, fontSize: 12, fontWeight: FontWeight.w500, shadows: [Shadow(color: c, blurRadius: 0)]);

  LineChartData _lineData(
    BuildContext context,
    CartesianModel m,
    FlTitlesData titles,
    FlGridData grid,
    FlBorderData border,
    ExtraLinesData extra,
    RangeAnnotations ranges,
    List<int> idx, {
    bool category = false,
  }) {
    final n = m.rows.length;
    final shared = spec.tooltip['shared'] != false;
    final bars = [
      for (final i in idx)
        LineChartBarData(
          spots: [
            for (var r = 0; r < n; r++) m.y[i][r] == null ? FlSpot.nullSpot : FlSpot(m.xs[r], m.y[i][r]!),
          ],
          color: spec.colorOf(i),
          barWidth: spec.flNum('lineWidth') ?? 2,
          isCurved: spec.series[i].smooth,
          curveSmoothness: spec.flNum('curveSmoothness') ?? 0.3,
          preventCurveOverShooting: true,
          dashArray: spec.series[i].dashed ? const [6, 4] : null,
          dotData: FlDotData(
            show: spec.flBool('showDots') ?? n <= 31,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: spec.flNum('dotSize') ?? 2.5, color: spec.colorOf(i), strokeWidth: 0),
          ),
          belowBarData: BarAreaData(
            show: spec.series[i].area || spec.type == 'area',
            color: spec.colorOf(i).withValues(alpha: 0.15),
          ),
        ),
    ];
    final xMin = spec.flNum('minX') ?? (category || !spec.xNumeric ? (category ? -0.5 : 0.0) : null);
    final xMax = spec.flNum('maxX') ?? (category ? n - 0.5 : (!spec.xNumeric ? math.max(0, n - 1).toDouble() : null));
    return LineChartData(
      lineBarsData: bars,
      minY: m.left.min,
      maxY: m.left.max,
      minX: xMin,
      maxX: xMax == xMin ? null : xMax,
      titlesData: titles,
      gridData: grid,
      borderData: border,
      extraLinesData: extra,
      rangeAnnotations: ranges,
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => _tooltipBg(context),
          maxContentWidth: 220,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) => [
            for (final (k, s) in spots.indexed)
              (!shared && k > 0)
                  ? null
                  : LineTooltipItem(
                      '${k == 0 ? '${spec.xLabel(m.xValue(s.spotIndex))}\n' : ''}${spec.tooltipText(spec.series[idx[s.barIndex]], m.raw[idx[s.barIndex]][s.spotIndex], m.xValue(s.spotIndex))}',
                      _tooltipStyle(context, s.bar.color ?? Colors.white),
                    ),
          ],
        ),
      ),
    );
  }

  BarChartData _barData(
    BuildContext context,
    CartesianModel m,
    FlTitlesData titles,
    FlGridData grid,
    FlBorderData border,
    ExtraLinesData extra,
    RangeAnnotations ranges,
    List<int> idx,
  ) {
    final n = m.rows.length;
    final stacked = spec.type == 'stackedBar';
    final radius = BorderRadius.vertical(top: Radius.circular(spec.flNum('barRadius') ?? 2));
    final width = spec.flNum('barWidth') ?? (stacked ? 18 : math.max(4, 28 / math.max(1, idx.length)).toDouble());
    final labelStyle = _small(context).copyWith(color: ShadTheme.of(context).colorScheme.foreground);
    BarChartRodLabel label(int i, int r) {
      final show = spec.series[i].labels ?? spec.showLabels;
      if (!show || m.raw[i][r] == null) return const BarChartRodLabel(show: false);
      return BarChartRodLabel(show: true, text: spec.labelText(spec.series[i], m.raw[i][r], m.xValue(r)), style: labelStyle, offset: const Offset(0, -2));
    }

    final groups = <BarChartGroupData>[];
    for (var r = 0; r < n; r++) {
      final rods = <BarChartRodData>[];
      if (stacked) {
        final byStack = <String, List<int>>{};
        for (final i in idx) {
          byStack.putIfAbsent(spec.series[i].stack ?? '_', () => []).add(i);
        }
        for (final g in byStack.values) {
          var acc = 0.0;
          final items = <BarChartRodStackItem>[];
          for (final i in g) {
            final v = math.max(0.0, m.y[i][r] ?? 0);
            items.add(BarChartRodStackItem(acc, acc + v, spec.colorOf(i)));
            acc += v;
          }
          rods.add(BarChartRodData(toY: acc, rodStackItems: items, width: width, borderRadius: BorderRadius.zero, color: Colors.transparent));
        }
      } else {
        for (final i in idx) {
          rods.add(BarChartRodData(toY: m.y[i][r] ?? 0, color: spec.colorOf(i), width: width, borderRadius: radius, label: label(i, r)));
        }
      }
      groups.add(BarChartGroupData(x: r, barRods: rods, barsSpace: 2));
    }
    return BarChartData(
      barGroups: groups,
      alignment: BarChartAlignment.spaceAround,
      minY: m.left.min,
      maxY: m.left.max,
      titlesData: titles,
      gridData: grid,
      borderData: border,
      extraLinesData: extra,
      rangeAnnotations: RangeAnnotations(horizontalRangeAnnotations: ranges.horizontalRangeAnnotations),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => _tooltipBg(context),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, gi, rod, ri) {
            final r = group.x;
            final lines = stacked
                ? [for (final i in idx) spec.tooltipText(spec.series[i], m.raw[i][r], m.xValue(r))]
                : [spec.tooltipText(spec.series[idx[ri]], m.raw[idx[ri]][r], m.xValue(r))];
            return BarTooltipItem('${spec.xLabel(m.xValue(r))}\n${lines.join('\n')}', _tooltipStyle(context, rod.color ?? Colors.white));
          },
        ),
      ),
    );
  }

  ScatterChartData _scatterData(BuildContext context, CartesianModel m, FlTitlesData titles, FlGridData grid, FlBorderData border) {
    final spots = <ScatterSpot>[];
    final owner = <(int, int)>[];
    for (var i = 0; i < spec.series.length; i++) {
      for (var r = 0; r < m.rows.length; r++) {
        final y = m.y[i][r];
        if (y == null) continue;
        spots.add(ScatterSpot(m.xs[r], y, dotPainter: FlDotCirclePainter(radius: spec.flNum('dotSize') ?? 5, color: spec.colorOf(i).withValues(alpha: 0.8), strokeWidth: 0)));
        owner.add((i, r));
      }
    }
    final xr = niceRange(m.xs, min: spec.flNum('minX'), max: spec.flNum('maxX'));
    return ScatterChartData(
      scatterSpots: spots,
      minX: xr.min,
      maxX: xr.max,
      minY: m.left.min,
      maxY: m.left.max,
      titlesData: titles,
      gridData: grid,
      borderData: border,
      scatterTouchData: ScatterTouchData(
        touchTooltipData: ScatterTouchTooltipData(
          getTooltipColor: (_) => _tooltipBg(context),
          getTooltipItems: (s) {
            final k = spots.indexOf(s);
            if (k < 0) return null;
            final (i, r) = owner[k];
            return ScatterTooltipItem(spec.tooltipText(spec.series[i], m.raw[i][r], m.xValue(r)), textStyle: _tooltipStyle(context, Colors.white));
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ pie / donut / gauge / radar

  Widget _pie(BuildContext context) {
    final s = spec.series.first;
    final values = [for (final r in rows) math.max(0.0, toDouble(lookup(r, s.field)) ?? 0)];
    final total = values.fold<double>(0, (a, b) => a + b);
    final donut = spec.type == 'donut';
    final show = spec.labels.isEmpty ? true : spec.showLabels;
    return LayoutBuilder(builder: (context, box) {
      final size = math.min(box.maxWidth, spec.height);
      final hole = spec.flNum('centerSpaceRadius') ?? (donut ? size * 0.22 : 0);
      final radius = spec.flNum('pieRadius') ?? math.max(20.0, size / 2 - hole - 12);
      return PieChart(
        PieChartData(
          centerSpaceRadius: hole,
          sectionsSpace: spec.flNum('sectionsSpace') ?? 1,
          sections: [
            for (var i = 0; i < rows.length; i++)
              PieChartSectionData(
                value: values[i] == 0 && total == 0 ? 1 : values[i],
                color: spec.palette[i % spec.palette.length],
                radius: radius,
                showTitle: show && values[i] > 0,
                title: spec.labelText(s, lookup(rows[i], s.field), lookup(rows[i], spec.xField), percent: total == 0 ? 0 : values[i] / total),
                titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                titlePositionPercentageOffset: donut ? 0.55 : 0.6,
              ),
          ],
        ),
        duration: _anim,
      );
    });
  }

  Widget _gauge(BuildContext context) {
    final s = spec.series.first;
    final row = rows.first;
    final raw = lookup(row, s.field);
    final v = toDouble(raw) ?? 0;
    final max = toDouble(row['max']) ?? 100;
    final ratio = (max <= 0 ? 0 : v / max).clamp(0, 1).toDouble();
    final cs = ShadTheme.of(context).colorScheme;
    final color = spec.colorOf(0);
    return LayoutBuilder(builder: (context, box) {
      final size = math.min(box.maxWidth, spec.height * 1.6);
      final hole = spec.flNum('centerSpaceRadius') ?? size * 0.28;
      final radius = spec.flNum('pieRadius') ?? math.max(12.0, size * 0.1);
      return Stack(alignment: Alignment.center, children: [
        PieChart(
          PieChartData(
            startDegreeOffset: 180,
            centerSpaceRadius: hole,
            sectionsSpace: 0,
            pieTouchData: PieTouchData(enabled: false),
            sections: [
              PieChartSectionData(value: ratio * 50 + 0.0001, color: color, radius: radius, showTitle: false),
              PieChartSectionData(value: (1 - ratio) * 50 + 0.0001, color: cs.muted, radius: radius, showTitle: false),
              PieChartSectionData(value: 50, color: Colors.transparent, radius: radius, showTitle: false),
            ],
          ),
          duration: _anim,
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(spec.valueText(s, raw), style: ShadTheme.of(context).textTheme.h3.copyWith(color: color)),
          Text(s.name, style: _small(context)),
        ]),
      ]);
    });
  }

  Widget _radar(BuildContext context) {
    if (rows.length < 3) return Center(child: Text(spec.emptyText, style: ShadTheme.of(context).textTheme.muted));
    final cs = ShadTheme.of(context).colorScheme;
    return RadarChart(
      RadarChartData(
        dataSets: [
          for (var i = 0; i < spec.series.length; i++)
            RadarDataSet(
              fillColor: spec.colorOf(i).withValues(alpha: 0.15),
              borderColor: spec.colorOf(i),
              borderWidth: spec.flNum('lineWidth') ?? 2,
              entryRadius: spec.flNum('dotSize') ?? 2,
              dataEntries: [for (final r in rows) RadarEntry(value: toDouble(lookup(r, spec.series[i].field)) ?? 0)],
            ),
        ],
        radarShape: RadarShape.polygon,
        radarBorderData: BorderSide(color: cs.border),
        gridBorderData: BorderSide(color: cs.border),
        tickBorderData: BorderSide(color: cs.border),
        tickCount: 4,
        ticksTextStyle: const TextStyle(fontSize: 9, color: Colors.transparent),
        titleTextStyle: _small(context),
        getTitle: (i, angle) => RadarChartTitle(text: spec.xLabel(lookup(rows[i], spec.xField))),
      ),
      duration: _anim,
    );
  }
}

num _num(double v) => v == v.roundToDouble() ? v.round() : v;
