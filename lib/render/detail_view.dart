import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import 'action_runner.dart';
import 'blocks/block_scope.dart';
import 'blocks/blocks.dart';
import 'components/cells.dart';
import 'page_desc.dart';
import 'render_api.dart';
import 'template.dart';
import '../core/i18n.dart';

/// Detail page (RENDER.md §6.4): loads the record from `load` (`{id}` from the route params),
/// header (title template, tag columns, actions with visibleWhen / hiddenWhen), then tabs of blocks
/// (only the selected tab is built) or plain blocks. Blocks see `{field}` of record ∪ params.
class DetailView extends ConsumerStatefulWidget {
  const DetailView({super.key, required this.desc, this.params = const {}});

  final PageDesc desc;
  final Map<String, dynamic> params;

  @override
  ConsumerState<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends ConsumerState<DetailView> {
  final RefreshBus _bus = RefreshBus();
  late final BlockDataLoader _loader = BlockDataLoader((p) => ref.read(renderApiProvider).get(p));
  Json? _record;
  Object? _error;
  bool _loading = true;
  int _tab = 0;

  Json get _body => widget.desc.body;

  /// Record ∪ params, rebuilt only when the record is (re)loaded so blocks keep their data.
  late Json _data = {...widget.params};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = _body['load'] is String ? fillPath(_body['load'] as String, widget.params) : null;
    if (path == null) {
      setState(() {
        _loading = false;
        _error = tr('缺少参数，无法加载详情');
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await ref.read(renderApiProvider).get(path);
      if (!mounted) return;
      setState(() {
        _record = r is Map ? r.cast<String, dynamic>() : <String, dynamic>{};
        _data = {...widget.params, ..._record!};
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await _load();
    _bus.refresh();
  }

  ActionRunner _runner(BuildContext context) => ActionRunner(
        context: context,
        ref: ref,
        onRefresh: _refreshAll,
        onRefreshTarget: _bus.refresh,
      );

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (_record == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(LucideIcons.triangleAlert, size: 28, color: t.colorScheme.mutedForeground),
          const SizedBox(height: 8),
          Text(tr('详情加载失败'), style: t.textTheme.large),
          const SizedBox(height: 4),
          Text('${_error ?? ''}', style: t.textTheme.muted),
          const SizedBox(height: 12),
          ShadButton.outline(onPressed: _load, child: Text(tr('重试'))),
        ]),
      );
    }
    final data = _data;
    final header = asJson(_body['header']);
    final tabs = asJsonList(_body['tabs']);
    final tab = tabs.isEmpty ? null : tabs[_tab.clamp(0, tabs.length - 1)];
    final blocks = tab != null ? asJsonList(tab['blocks']) : asJsonList(_body['blocks']);
    final canPop = GoRouter.maybeOf(context)?.canPop() ?? Navigator.of(context).canPop();

    return BlockScope(
      data: data,
      bus: _bus,
      loader: _loader,
      onAction: (a, d) => _runner(context).run(a, d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (canPop)
              ShadButton.ghost(
                size: ShadButtonSize.sm,
                leading: const Icon(LucideIcons.arrowLeft, size: 16),
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(tr('返回')),
              ),
            Text(widget.desc.title, style: t.textTheme.muted),
          ]),
        ),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(child: Text(fillText('${header['title'] ?? widget.desc.title}', data), style: t.textTheme.h4, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
          for (final c in asJsonList(header['tags']))
            Padding(padding: const EdgeInsets.only(right: 6), child: SizedBox(height: 24, child: buildCell(context, c, data))),
          const Spacer(),
          Wrap(spacing: 8, children: [
            for (final a in asJsonList(header['actions']))
              if (actionVisible(a, data)) actionButton(a, () => _runner(context).run(a, data), label: fillText('${a['label']}', data)),
          ]),
        ]),
        const SizedBox(height: 12),
        if (tabs.isNotEmpty) ...[
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (i, tb) in tabs.indexed)
                  MergeSemantics(
                    child: Semantics(
                      button: true,
                      selected: i == _tab,
                      child: GestureDetector(
                    key: ValueKey('detail-tab-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _tab = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(width: 2, color: i == _tab ? t.colorScheme.primary : Colors.transparent)),
                      ),
                      child: Text(
                        fillText('${tb['title'] ?? ''}', data),
                        style: TextStyle(fontSize: 14, fontWeight: i == _tab ? FontWeight.w600 : FontWeight.normal, color: i == _tab ? t.colorScheme.foreground : t.colorScheme.mutedForeground),
                      ),
                    ),
                  ),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey('detail-tab-body-$_tab'),
            padding: const EdgeInsets.only(bottom: 24, right: 4),
            child: KeyedSubtree(key: ValueKey('tab-$_tab'), child: BlockGrid(blocks: blocks)),
          ),
        ),
      ]),
    );
  }
}
