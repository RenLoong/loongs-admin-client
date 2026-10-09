import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../widgets/common.dart';
import 'action_runner.dart';
import 'blocks/block_scope.dart';
import 'blocks/blocks.dart';
import 'page_desc.dart';
import 'render_api.dart';
import '../core/i18n.dart';

/// Dashboard page (RENDER.md §6.1): 24-column block grid; every block loads its own API
/// (same path shared), refreshes on its own (`refresh` seconds / `refresh` action target) and fails
/// on its own. The header 刷新 button reloads every block.
class DashboardView extends ConsumerStatefulWidget {
  const DashboardView({super.key, required this.desc, this.params = const {}});

  final PageDesc desc;
  final Map<String, dynamic> params;

  @override
  ConsumerState<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends ConsumerState<DashboardView> {
  final RefreshBus _bus = RefreshBus();
  late final BlockDataLoader _loader = BlockDataLoader((p) => ref.read(renderApiProvider).get(p));

  @override
  void dispose() {
    _bus.dispose();
    super.dispose();
  }

  ActionRunner _runner(BuildContext context) => ActionRunner(
        context: context,
        ref: ref,
        onRefresh: () => _bus.refresh(),
        onRefreshTarget: _bus.refresh,
      );

  @override
  Widget build(BuildContext context) {
    final blocks = asJsonList(widget.desc.body['blocks']);
    return BlockScope(
      data: widget.params,
      bus: _bus,
      loader: _loader,
      onAction: (a, d) => _runner(context).run(a, d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: widget.desc.title, actions: [
          ShadButton.outline(
            leading: const Icon(LucideIcons.refreshCw, size: 16),
            onPressed: () => _bus.refresh(),
            child: Text(tr('刷新')),
          ),
        ]),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24, right: 4),
            child: BlockGrid(blocks: blocks),
          ),
        ),
      ]),
    );
  }
}
