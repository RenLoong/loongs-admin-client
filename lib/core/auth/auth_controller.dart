import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../api_client.dart';
import '../config.dart';
import '../models.dart';
import '../settings.dart';
import 'loopback.dart';
import 'oauth_client.dart';
import 'pkce.dart';
import 'token_set.dart';
import 'kv_store.dart';
import 'session_kv.dart';
import 'token_store.dart';
import '../../core/i18n.dart';

enum AuthStatus { unknown, signedOut, signedIn }

@immutable
class AuthState {
  const AuthState({
    required this.status,
    this.tokens,
    this.profile,
    this.menus = const [],
    this.busy = false,
    this.error,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  const AuthState.signedOut({String? error})
      : this(status: AuthStatus.signedOut, error: error);

  final AuthStatus status;
  final TokenSet? tokens;
  final Profile? profile;
  final List<MenuNode> menus;
  final bool busy;
  final String? error;

  bool can(String code) => profile?.can(code) ?? false;

  AuthState copyWith({
    TokenSet? tokens,
    Profile? profile,
    List<MenuNode>? menus,
    bool? busy,
    String? error,
  }) =>
      AuthState(
        status: status,
        tokens: tokens ?? this.tokens,
        profile: profile ?? this.profile,
        menus: menus ?? this.menus,
        busy: busy ?? this.busy,
        error: error,
      );
}

/// Token storage per platform / web context (see kWebTokenStorage).
final tokenStoreProvider = Provider<TokenStore>((ref) {
  final secure = SecureKv(ref.watch(secureStorageProvider));
  if (!kIsWeb) return TokenStore(secure);
  return switch (resolveWebTokenStorage(kWebTokenStorage, secureContext: isSecureContext())) {
    'secure' => TokenStore(secure),
    'memory' => TokenStore(MemoryKv(), pending: sessionKv(), persistAccess: false),
    _ => TokenStore(sessionKv(), persistAccess: false),
  };
});
final oauthClientProvider = Provider<OAuthClient>((ref) => OAuthClient(ref.watch(baseUrlProvider)));

/// Session lifecycle: restore → PKCE login (web redirect / desktop loopback) → profile + menus,
/// single-flight refresh with rotation, logout (revoke).
class AuthController extends Notifier<AuthState> {
  Completer<String?>? _refreshing;

  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  TokenStore get _store => ref.read(tokenStoreProvider);
  OAuthClient get _oauth => ref.read(oauthClientProvider);

  Future<void> _restore() async {
    final t = await _store.read();
    if (t == null) {
      state = const AuthState.signedOut();
      return;
    }
    state = AuthState(status: AuthStatus.signedIn, tokens: t);
    try {
      await loadSession();
    } catch (_) {
      // loadSession signs out on a dead session; network errors keep the (unverified) session
      if (state.status == AuthStatus.signedIn && state.profile == null) {
        state = AuthState.signedOut(error: tr('会话恢复失败，请重新登录'));
      }
    }
  }

  /// Starts the authorization-code + PKCE flow in the system browser.
  /// Web: same-tab redirect, completed by [completeWebCallback]. Desktop: loopback listener.
  Future<void> login() async {
    if (state.busy) return;
    state = AuthState(status: AuthStatus.signedOut, busy: true);
    final pkce = Pkce.generate();
    final st = randomUrlSafe(16);
    try {
      if (kIsWeb) {
        // e.g. http://127.0.0.1:21080/#/login → http://127.0.0.1:21080/callback.html
        final redirect = Uri.base.resolve(kWebCallbackFile).toString();
        await _store.savePending({'verifier': pkce.verifier, 'state': st, 'redirect_uri': redirect});
        await launchUrl(_authorizeUrl(redirect, pkce, st), webOnlyWindowName: '_self');
        return;
      }
      final rx = await LoopbackReceiver.start();
      final redirect = rx.redirectUri; // keep before waitForCallback closes the socket
      final url = _authorizeUrl(redirect, pkce, st);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        await rx.close();
        throw OAuthError('browser_unavailable', tr('无法打开系统浏览器'));
      }
      final q = await rx.waitForCallback(const Duration(minutes: 5));
      await _finish(q, verifier: pkce.verifier, state: st, redirectUri: redirect);
    } catch (e) {
      state = AuthState.signedOut(error: _describe(e));
    }
  }

  /// The authorize URL with the user's language / theme for the server-rendered login page.
  Uri _authorizeUrl(String redirect, Pkce pkce, String st) {
    final s = ref.read(settingsProvider);
    return _oauth.authorizeUrl(redirectUri: redirect, pkce: pkce, state: st, uiLocales: s.language, uiTheme: s.uiTheme);
  }

  /// Web: `callback.html` forwarded `?code&state` to `#/auth/callback`.
  Future<void> completeWebCallback(Map<String, String> q) async {
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    final p = await _store.takePending();
    try {
      if (p == null) throw OAuthError('invalid_request', tr('登录请求已失效，请重试'));
      await _finish(q, verifier: p['verifier']!, state: p['state']!, redirectUri: p['redirect_uri']!);
    } catch (e) {
      state = AuthState.signedOut(error: _describe(e));
    }
  }

  Future<void> _finish(
    Map<String, String> q, {
    required String verifier,
    required String state,
    required String redirectUri,
  }) async {
    if (q['error'] != null) throw OAuthError(q['error']!, q['error_description']);
    if (q['state'] != state) throw OAuthError('invalid_state', tr('state 不匹配，已拒绝'));
    final code = q['code'];
    if (code == null || code.isEmpty) throw OAuthError('invalid_request', tr('缺少授权码'));
    final t = await _oauth.exchangeCode(code: code, verifier: verifier, redirectUri: redirectUri);
    await _store.write(t);
    this.state = AuthState(status: AuthStatus.signedIn, tokens: t);
    await loadSession();
  }

  /// Loads profile + dynamic menus (also used after permission changes).
  Future<void> loadSession() async {
    final api = ref.read(apiProvider);
    try {
      final me = Profile.fromJson(((await api.get('/auth/me')) as Map).cast<String, dynamic>());
      final menus = ((await api.get('/auth/menus')) as List)
          .map((e) => MenuNode.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      if (state.status == AuthStatus.signedIn) {
        state = state.copyWith(profile: me, menus: menus);
      }
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _signOutLocal(tr('登录已失效：{msg}', {'msg': e.message}));
      }
      rethrow;
    }
  }

  /// Single-flight refresh. Returns the new access token, or null (session ended).
  /// [sentToken] lets concurrent 401s reuse a token refreshed meanwhile.
  Future<String?> refreshAccess({String? sentToken}) async {
    final cur = state.tokens;
    if (cur == null) return null;
    if (sentToken != null && sentToken != 'Bearer ${cur.accessToken}' && !cur.expiresSoon()) {
      return cur.accessToken;
    }
    final inflight = _refreshing;
    if (inflight != null) return inflight.future;
    final c = _refreshing = Completer<String?>();
    try {
      final rt = cur.refreshToken;
      if (rt == null) throw OAuthError('invalid_grant', 'no refresh token');
      final t = await _oauth.refresh(rt); // rotated: old refresh token is now spent
      await _store.write(t);
      state = state.copyWith(tokens: t);
      c.complete(t.accessToken);
    } on OAuthError catch (e) {
      if (e.isFatal) await _signOutLocal(tr('登录已过期，请重新登录'));
      c.complete(null);
    } catch (_) {
      c.complete(null);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  Future<void> logout() async {
    final rt = state.tokens?.refreshToken;
    await _signOutLocal(null);
    if (rt != null) {
      try {
        await _oauth.revoke(rt);
      } catch (_) {}
    }
  }

  Future<void> _signOutLocal(String? reason) async {
    await _store.clear();
    state = AuthState.signedOut(error: reason);
  }

  static String _describe(Object e) => switch (e) {
        OAuthError(:final error, :final description) => description ?? error,
        TimeoutException() => tr('登录超时，请重试'),
        _ => e.toString(),
      };
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
