import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/api_client.dart';
import 'health_repository.dart';
import '../../core/i18n.dart';

class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage> {
  late final TextEditingController _url =
      TextEditingController(text: ref.read(baseUrlProvider));

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _check() {
    final v = _url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (v.isNotEmpty && v != ref.read(baseUrlProvider)) {
      ref.read(baseUrlProvider.notifier).set(v);
    }
    ref.invalidate(healthProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final health = ref.watch(healthProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: tr('返回'),
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/login');
            }
          },
        ),
        title: Text(tr('检查后端健康状态')),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              ShadCard(
                title: Text(tr('LOONGS 平台管理')),
                description: Text(tr('P0 骨架：后端健康检查')),
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ShadInput(
                          controller: _url,
                          placeholder: const Text('http://127.0.0.1:21000'),
                          onSubmitted: (_) => _check(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ShadButton(
                        onPressed: health.isLoading ? null : _check,
                        child: Text(tr('检查 /health')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              health.when(
                loading: () => ShadCard(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(tr('请求中…')),
                  ),
                ),
                error: (e, _) => ShadAlert.destructive(
                  title: Text(tr('请求失败')),
                  description: Text(_describe(e)),
                ),
                data: (r) => _ResultCard(result: r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _describe(Object e) {
    if (e is DioException) {
      return '${e.type.name}: ${e.message ?? e.error ?? ''}';
    }
    return e.toString();
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final HealthResult result;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final d = result.data;
    return ShadCard(
      title: Row(
        children: [
          Text(tr('状态')),
          const SizedBox(width: 12),
          result.ok
              ? ShadBadge(child: Text(result.status))
              : ShadBadge.destructive(child: Text(result.status)),
          const SizedBox(width: 12),
          Text(
            'HTTP ${result.httpStatus} · ${result.elapsedMs}ms',
            style: theme.textTheme.muted,
          ),
        ],
      ),
      description: Text(
        '${tr('应用 {app}（{env}）', {'app': d['app'], 'env': d['env']})} · PHP ${d['php']} · Swoole ${d['swoole']}',
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in result.checks.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${e.key}: ${(e.value as Map)['ok'] == true ? tr('正常') : tr('异常')}'
                  ' · ${(e.value as Map)['ms']}ms',
                ),
              ),
            const SizedBox(height: 12),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(result.body),
              style: theme.textTheme.small.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}