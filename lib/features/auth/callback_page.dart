import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/i18n.dart';

/// Web redirect target: web/callback.html forwards `?code&state` here (hash route).
class CallbackPage extends ConsumerStatefulWidget {
  const CallbackPage({super.key, required this.params});

  final Map<String, String> params;

  @override
  ConsumerState<CallbackPage> createState() => _CallbackPageState();
}

class _CallbackPageState extends ConsumerState<CallbackPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(authProvider.notifier).completeWebCallback(widget.params);
      if (!mounted) return;
      context.go(ref.read(authProvider).status == AuthStatus.signedIn ? '/' : '/login');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(tr('正在完成登录…')),
        ])),
      );
}
