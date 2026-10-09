import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/models.dart';
import 'page_desc.dart';
import 'render_page.dart';

/// Menu route → generic page when the menu node (menu.json) declares `page` + a rendered
/// `page_type`, otherwise [fallback] (hand-written page / 404). The template is chosen by the
/// menu's page_type; the description's `type` must match it.
class MenuRoutePage extends ConsumerWidget {
  const MenuRoutePage({super.key, required this.path, required this.fallback, this.params = const {}});

  final String path;
  final Widget fallback;
  final Map<String, dynamic> params;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.status == AuthStatus.signedIn && auth.profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final node = MenuNode.findByPath(auth.menus, path);
    if (node?.page != null && kRenderedPageTypes.contains(node!.pageType)) {
      return RenderPage(key: ValueKey('menu-${node.page}'), page: node.page!, params: params, expectType: node.pageType);
    }
    return fallback;
  }
}
