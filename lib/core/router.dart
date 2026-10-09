import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/callback_page.dart';
import '../features/auth/login_page.dart';
import '../features/health/health_page.dart';
import '../features/home/home_page.dart';
import '../features/shell/admin_shell.dart';
import '../render/menu_route_page.dart';
import '../render/render_page.dart';
import '../widgets/common.dart';
import 'auth/auth_controller.dart';

/// Page → permission code (menu `perms`). The server enforces the same codes; this only avoids
/// rendering pages the user can't use (deep links / stale bookmarks → /403).
const Map<String, String> kRoutePerms = {
  '/system/admins': 'system:admin:list',
  '/system/roles': 'system:role:list',
  '/system/menus': 'system:menu:list',
  '/system/depts': 'system:dept:list',
};

const _public = {'/login', '/auth/callback', '/health'};

/// Pure guard (unit-tested): returns a redirect target or null.
String? authRedirect(AuthState auth, Uri uri) {
  final loc = uri.path;
  if (loc == '/auth/callback' || loc == '/health') return null;
  switch (auth.status) {
    case AuthStatus.unknown:
      return loc == '/splash' ? null : '/splash';
    case AuthStatus.signedOut:
      return loc == '/login' ? null : '/login';
    case AuthStatus.signedIn:
      if (loc == '/login' || loc == '/splash') return '/';
      if (auth.profile == null) return null; // profile loading; page shows spinner
      final need = kRoutePerms[loc];
      if (need != null && !auth.can(need)) return '/403';
      return null;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) => authRedirect(ref.read(authProvider), state.uri),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(
        path: '/auth/callback',
        builder: (_, s) => CallbackPage(params: s.uri.queryParameters),
      ),
      GoRoute(path: '/health', builder: (_, _) => const HealthPage()),
      ShellRoute(
        builder: (_, s, child) => AdminShell(location: s.uri.path, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomePage()),
          GoRoute(path: '/403', builder: (_, _) => const ForbiddenPage()),
          // R4: every P1 system page is rendered from its menu.json page (admins / roles / menus /
          // depts); only registered custom pages (role-permission-editor) are hand-written.
          for (final p in const ['/system/admins', '/system/roles', '/system/menus', '/system/depts'])
            GoRoute(
              path: p,
              builder: (_, s) => MenuRoutePage(path: p, params: s.uri.queryParameters, fallback: const NotFoundPage()),
            ),
          // R3: 平台概览 (menu.json page admin.dashboard.overview, page_type dashboard).
          GoRoute(
            path: '/dashboard',
            builder: (_, s) => MenuRoutePage(path: '/dashboard', params: s.uri.queryParameters, fallback: const NotFoundPage()),
          ),
          // Generic pages by code (openForm mode "page", deep links): /p/admin.system.admin-form?id=3
          GoRoute(
            path: '/p/:page',
            builder: (_, s) => RenderPage(key: ValueKey(s.uri.toString()), page: s.pathParameters['page']!, params: s.uri.queryParameters),
          ),
        ],
      ),
    ],
    // Menu paths without a hand-written route: generic page if the menu declares one, else 404.
    errorBuilder: (_, s) => AdminShell(
      location: s.uri.path,
      child: MenuRoutePage(path: s.uri.path, params: s.uri.queryParameters, fallback: const NotFoundPage()),
    ),
  );
});

@visibleForTesting
Set<String> get publicRoutes => _public;
