import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api.dart';
import '../chart/chart_format.dart';
import '../chart/chart_spec.dart';
import '../chart/chart_view.dart';
import '../components/cells.dart';
import '../components/unknown.dart';
import '../page_desc.dart';
import '../render_repository.dart';
import '../table_view.dart';
import '../template.dart';
import 'block_scope.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';

typedef BlockBuilder = Widget Function(BuildContext context, Json block);

/// Block components of dashboard / detail pages (RENDER.md §6.1 / §6.4 / §7 区块).
/// Unknown components degrade to [UnknownComponent] and never break the page.
final Map<String, BlockBuilder> blockRegistry = {
  'stat': (ctx, b) => _Card(block: b, child: ApiBlock(block: b, builder: (ctx, data) => StatValue(block: b, data: data))),
  'chart': (ctx, b) => _Card(block: b, child: ChartBlock(block: b)),
  'rank': (ctx, b) => _Card(block: b, child: ApiBlock(block: b, builder: (ctx, data) => _Rank(block: b, rows: chartRows(data)))),
  'shortcuts': (ctx, b) => _Card(block: b, child: _Shortcuts(block: b)),
  'descriptions': (ctx, b) => _Card(block: b, child: Descriptions(block: b, record: BlockScope.of(ctx).data)),
  'table': (ctx, b) => _Card(block: b, padding: EdgeInsets.zero, child: EmbeddedTable(block: b)),
  'timeline': (ctx, b) => _Card(block: b, child: ApiBlock(block: b, builder: (ctx, data) => _Timeline(block: b, rows: chartRows(data)))),
  'markdown': (ctx, b) => _Card(block: b, child: _Markdown(block: b)),
  'alert': (ctx, b) => RenderAlert(block: b),
  'card': (ctx, b) => _Card(block: b, child: BlockGrid(blocks: asJsonList(b['blocks']))),
  'grid': (ctx, b) => BlockGrid(blocks: asJsonList(b['blocks'])),
  'collapse': (ctx, b) => _Card(block: b, child: _Collapse(panels: asJsonList(b['panels']))),
};

Widget buildBlock(BuildContext context, Json block) {
  final b = blockRegistry['${block['component']}'];
  if (b == null) return UnknownComponent(tr('区块'), '${block['component']}');
  return KeyedSubtree(key: ValueKey('block-${block['id'] ?? block['title'] ?? block['component']}'), child: b(context, block));
}

/// 24-column layout: `span` per block (default 24); stacked (full width) below 720px or on mobile
/// descriptions (no span).
class BlockGrid extends StatelessWidget {
  const BlockGrid({super.key, required this.blocks, this.gap = 12});

  final List<Json> blocks;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 1200.0;
      final narrow = w < 720;
      // Rows of spans so items in one row share the height of the tallest one.
      final rows = <List<Json>>[];
      var used = 0;
      for (final b in blocks) {
        final span = narrow ? 24 : ((b['span'] as num?)?.toInt() ?? 24).clamp(1, 24);
        if (rows.isEmpty || used + span > 24) {
          rows.add([]);
          used = 0;
        }
        rows.last.add(b);
        used += span;
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          if (r.isNotEmpty && r.every((b) => b['component'] == 'stat'))
            MetricStrip(blocks: r)
          else
            IntrinsicHeightSafe(
            children: [
              for (final b in r)
                (
                  flex: narrow ? 24 : ((b['span'] as num?)?.toInt() ?? 24).clamp(1, 24),
                  child: buildBlock(context, b),
                ),
            ],
            remainder: narrow ? 0 : 24 - r.fold<int>(0, (s, b) => s + ((b['span'] as num?)?.toInt() ?? 24).clamp(1, 24)),
            gap: gap,
          ),
        ],
      ]);
    });
  }
}

/// A row of flex children (no IntrinsicHeight: charts / grids inside cannot report intrinsics).
class IntrinsicHeightSafe extends StatelessWidget {
  const IntrinsicHeightSafe({super.key, required this.children, required this.remainder, required this.gap});

  final List<({int flex, Widget child})> children;
  final int remainder;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, c) in children.indexed) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(flex: c.flex, child: c.child),
      ],
      if (remainder > 0) Spacer(flex: remainder),
    ]);
  }
}


class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.blocks});

  final List<Json> blocks;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppleColors.of(context).blue, borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Row(children: [
        for (final b in blocks)
          Expanded(child: ApiBlock(block: b, builder: (ctx, data) => StatValue(block: b, data: data, onBlue: true))),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.block, required this.child, this.padding = const EdgeInsets.all(16)});

  final Json block;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final title = block['title'] is String ? fillText(block['title'] as String, BlockScope.of(context).data) : null;
    return Container(
      decoration: BoxDecoration(
        color: t.colorScheme.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: appleShadow(t.brightness),
      ),
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (title != null && title.isNotEmpty && block['component'] != 'stat')
          Padding(
            padding: padding == EdgeInsets.zero ? const EdgeInsets.fromLTRB(16, 12, 16, 0) : const EdgeInsets.only(bottom: 12),
            child: Text(title, style: t.textTheme.large.copyWith(fontSize: 15)),
          ),
        child,
      ]),
    );
  }
}

/// Loads `block.api` (with `{field}` from the scope) and builds [builder] with the response data.
/// Shows its own loading / error + retry; reloads on page refresh, `refresh(target: id)` and every
/// `block.refresh` seconds. One failing block never affects the others.
class ApiBlock extends StatefulWidget {
  const ApiBlock({super.key, required this.block, required this.builder, this.minHeight = 48});

  final Json block;
  final Widget Function(BuildContext context, Object? data) builder;
  final double minHeight;

  @override
  State<ApiBlock> createState() => _ApiBlockState();
}

class _ApiBlockState extends State<ApiBlock> {
  BlockScope? _scope;
  Object? _data;
  Object? _error;
  bool _loading = true;
  Timer? _timer;
  int _seq = 0;

  String? get _path => widget.block['api'] is String ? fillPath(widget.block['api'] as String, _scope!.data) : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = BlockScope.of(context);
    if (!identical(s.bus, _scope?.bus)) {
      _scope?.bus.removeListener(_onBus);
      s.bus.addListener(_onBus);
    }
    final first = _scope == null;
    final dataChanged = !first && _scope!.data != s.data;
    _scope = s;
    if (first || dataChanged) _load(generation: s.bus.generation);
    _timer ??= _startTimer();
  }

  Timer? _startTimer() {
    final secs = (widget.block['refresh'] as num?)?.toInt() ?? 0;
    if (secs < 5) return null;
    return Timer.periodic(Duration(seconds: secs), (_) => _load(force: true, silent: true));
  }

  void _onBus() {
    final bus = _scope!.bus;
    if (bus.target == null || bus.target == widget.block['id']) {
      _load(generation: bus.generation, silent: _data != null);
    }
  }

  Future<void> _load({int generation = 0, bool force = false, bool silent = false}) async {
    final path = _path;
    final seq = ++_seq;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = widget.block['api'] == null ? null : tr('缺少参数，无法加载');
      });
      return;
    }
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final d = await _scope!.loader.load(path, generation: generation, force: force);
      if (!mounted || seq != _seq) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scope?.bus.removeListener(_onBus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (_loading && _data == null) {
      return SizedBox(height: widget.minHeight, child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_error != null) {
      return SizedBox(
        height: math.max(widget.minHeight, 72),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('加载失败：{error}', {'error': _error}), style: TextStyle(fontSize: 12, color: t.colorScheme.destructive), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ShadButton.outline(
              size: ShadButtonSize.sm,
              onPressed: () => _load(generation: _scope!.bus.generation, force: true),
              child: Text(tr('重试')),
            ),
          ]),
        ),
      );
    }
    return widget.builder(context, _data);
  }
}

// ------------------------------------------------------------------ stat

/// Stat card: `title`, `{field}` value through `format` (default `{value|thousands}`), optional
/// trend ratio read from `<field>_<trend>` (then `<trend>`) — e.g. admins_mom: 0.125 → ↑ 12.5% 环比.
class StatValue extends StatelessWidget {
  const StatValue({super.key, required this.block, required this.data, this.onBlue = false});

  final Json block;
  final Object? data;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final d = data is Map ? (data as Map).cast<String, dynamic>() : <String, dynamic>{'value': data};
    final field = '${block['field'] ?? 'value'}';
    final v = lookup(d, field);
    final text = v == null ? '—' : formatTemplate('${block['format'] ?? '{value|thousands}'}', {'value': v});
    final trend = block['trend'] as String?;
    final ratio = trend == null ? null : toDouble(lookup(d, '${field}_$trend') ?? lookup(d, trend));
    final label = switch (trend) { 'mom' => tr('环比'), 'yoy' => tr('同比'), _ => tr('较上期') };
    final up = (ratio ?? 0) >= 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(fillText('${block['title'] ?? ''}', BlockScope.of(context).data),
          style: onBlue ? t.textTheme.muted.copyWith(color: Colors.white.withValues(alpha: 0.85)) : t.textTheme.muted),
      const SizedBox(height: 6),
      Text(text, style: onBlue ? t.textTheme.h3.copyWith(color: Colors.white) : t.textTheme.h3),
      if (ratio != null) ...[
        const SizedBox(height: 4),
        Text(
          '${ratio == 0 ? '—' : (up ? '↑' : '↓')} ${(ratio.abs() * 100).toStringAsFixed(1)}% $label',
          style: TextStyle(fontSize: 12, color: ratio == 0 ? t.colorScheme.mutedForeground : (up ? AppleColors.of(context).green : t.colorScheme.destructive)),
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ chart

/// Chart block: loads `api` (list, `{list}` or one object) and draws [RenderChart];
/// `Chart::custom` without api goes straight to the custom registry.
class ChartBlock extends StatelessWidget {
  const ChartBlock({super.key, required this.block});

  final Json block;

  @override
  Widget build(BuildContext context) {
    final spec = ChartSpec(block, dark: ShadTheme.of(context).brightness == Brightness.dark);
    if (block['api'] == null) return RenderChart(spec: spec, rows: chartRows(block['data']));
    return ApiBlock(block: block, minHeight: spec.height, builder: (ctx, data) => RenderChart(spec: spec, rows: chartRows(data)));
  }
}

// ------------------------------------------------------------------ rank

class _Rank extends StatelessWidget {
  const _Rank({required this.block, required this.rows});

  final Json block;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final limit = (block['limit'] as num?)?.toInt() ?? 10;
    final label = '${block['label'] ?? 'name'}', value = '${block['value'] ?? 'value'}';
    final list = rows.take(limit).toList();
    if (list.isEmpty) return SizedBox(height: 48, child: Center(child: Text(tr('暂无数据'), style: t.textTheme.muted)));
    final max = list.map((r) => toDouble(lookup(r, value)) ?? 0).fold<double>(0, math.max);
    final fmt = block['format'] as String?;
    return Column(children: [
      for (final (i, r) in list.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: i < 3 ? t.colorScheme.primary : t.colorScheme.muted, borderRadius: BorderRadius.circular(10)),
              child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: i < 3 ? t.colorScheme.primaryForeground : t.colorScheme.foreground)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(cellText(lookup(r, label)), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  Text(
                    fmt != null ? formatTemplate(fmt, {'value': lookup(r, value)}) : plainNumber(toDouble(lookup(r, value)) ?? 0),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ]),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: max <= 0 ? 0 : (toDouble(lookup(r, value)) ?? 0) / max,
                    minHeight: 4,
                    backgroundColor: t.colorScheme.muted,
                    color: t.colorScheme.primary,
                  ),
                ),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ shortcuts

IconData shortcutIcon(String? name) => switch (name) {
      'users' => LucideIcons.users,
      'shield' => LucideIcons.shield,
      'building' => LucideIcons.building,
      'refresh-cw' => LucideIcons.refreshCw,
      'plus' => LucideIcons.plus,
      'settings' => LucideIcons.settings,
      'file' => LucideIcons.file,
      _ => LucideIcons.arrowRight,
    };

class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.block});

  final Json block;

  @override
  Widget build(BuildContext context) {
    final scope = BlockScope.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final it in asJsonList(block['items']))
        ShadButton.outline(
          leading: Icon(shortcutIcon(it['icon'] as String?), size: 16),
          onPressed: () => scope.onAction({'label': it['title'], ...asJson(it['action'])}, scope.data),
          child: Text(fillText('${it['title'] ?? ''}', scope.data)),
        ),
    ]);
  }
}

// ------------------------------------------------------------------ descriptions

/// Label / value grid of [record] with the column renderers (`columns` per row; 1 below 600px).
class Descriptions extends StatelessWidget {
  const Descriptions({super.key, required this.block, required this.record});

  final Json block;
  final Json record;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final items = asJsonList(block['items']);
    return LayoutBuilder(builder: (context, box) {
      final want = (block['columns'] as num?)?.toInt() ?? 3;
      final cols = box.maxWidth < 600 ? 1 : want.clamp(1, 4);
      final w = (box.maxWidth - (cols - 1) * 16) / cols;
      return Wrap(spacing: 16, runSpacing: 12, children: [
        for (final c in items)
          SizedBox(
            width: w,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 88, child: Text('${c['label'] ?? c['field']}', style: t.textTheme.muted)),
              Expanded(
                child: c['component'] == 'text' || c['component'] == 'datetime' || c['component'] == 'money' || c['component'] == null
                    ? Text(columnText(c, record).isEmpty ? '—' : columnText(c, record), style: const TextStyle(fontSize: 14))
                    : SizedBox(height: 22, child: buildCell(context, c, record)),
              ),
            ]),
          ),
      ]);
    });
  }
}

// ------------------------------------------------------------------ table (embedded page)

/// `Block::table(page, params)`: the table page (its own description, ETag cached) with
/// `params` (`{id}` from the record) sent with every data request.
class EmbeddedTable extends ConsumerWidget {
  const EmbeddedTable({super.key, required this.block, this.height = 460});

  final Json block;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = fillParams(block['params'], BlockScope.of(context).data);
    final req = PageRequest('${block['page']}', params);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ref.watch(pageDescProvider(req)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(tr('表格加载失败：{error}', {'error': e}), style: TextStyle(color: ShadTheme.of(context).colorScheme.destructive))),
              data: (d) => d.type == 'table'
                  ? RenderTableView(key: ValueKey('embedded-${d.page}-${d.version}-${req.cacheKey}'), desc: d, params: params, embedded: true)
                  : Center(child: UnknownComponent(tr('区块'), 'table:${d.type}')),
            ),
      ),
    );
  }
}

// ------------------------------------------------------------------ timeline / markdown / alert / collapse

class _Timeline extends StatelessWidget {
  const _Timeline({required this.block, required this.rows});

  final Json block;
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (rows.isEmpty) return SizedBox(height: 48, child: Center(child: Text(tr('暂无记录'), style: t.textTheme.muted)));
    final time = '${block['time'] ?? 'time'}', content = '${block['content'] ?? 'content'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, r) in rows.indexed)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 20,
            child: Column(children: [
              Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: t.colorScheme.primary, shape: BoxShape.circle)),
              if (i < rows.length - 1) Container(width: 2, height: 40, color: t.colorScheme.border),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cellText(lookup(r, content)), style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(formatDateTime(lookup(r, time), 'yyyy-MM-dd HH:mm'), style: t.textTheme.muted.copyWith(fontSize: 12)),
              ]),
            ),
          ),
        ]),
    ]);
  }
}

class _Markdown extends StatelessWidget {
  const _Markdown({required this.block});

  final Json block;

  @override
  Widget build(BuildContext context) {
    final text = fillText('${block['content'] ?? ''}', BlockScope.of(context).data);
    final paras = text.split(RegExp(r'\n\s*\n')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final p in paras)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(p.replaceAll('**', '').replaceAll(RegExp(r'^#+\s*'), ''), style: const TextStyle(fontSize: 14, height: 1.5)),
        ),
    ]);
  }
}

class RenderAlert extends StatelessWidget {
  const RenderAlert({super.key, required this.block});

  final Json block;

  @override
  Widget build(BuildContext context) {
    final data = BlockScope.of(context).data;
    final apple = AppleColors.of(context);
    final (Color color, IconData icon) = switch (block['type']) {
      'success' => (apple.green, LucideIcons.circleCheck),
      'warning' => (apple.orange, LucideIcons.triangleAlert),
      'error' => (apple.red, LucideIcons.circleX),
      _ => (apple.blue, LucideIcons.info),
    };
    final title = block['title'] is String ? fillText(block['title'] as String, data) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 13)),
            Text(fillText('${block['message'] ?? ''}', data), style: const TextStyle(fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _Collapse extends StatefulWidget {
  const _Collapse({required this.panels});

  final List<Json> panels;

  @override
  State<_Collapse> createState() => _CollapseState();
}

class _CollapseState extends State<_Collapse> {
  final Set<int> _open = {0};

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, p) in widget.panels.indexed) ...[
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open.contains(i) ? _open.remove(i) : _open.add(i)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(_open.contains(i) ? LucideIcons.chevronDown : LucideIcons.chevronRight, size: 16),
              const SizedBox(width: 6),
              Text('${p['title'] ?? ''}', style: t.textTheme.small),
            ]),
          ),
        ),
        if (_open.contains(i)) BlockGrid(blocks: asJsonList(p['blocks'])),
      ],
    ]);
  }
}
