import 'dart:convert';

import 'kv_store.dart';
import 'token_set.dart';

/// Tokens + in-flight PKCE state.
///
/// [persistAccess] = false (web without secure context, see kWebTokenStorage): the access token is
/// kept in memory only and [tokens] persists just the refresh token (+ nothing that can call the
/// API by itself); after a reload the session continues with a refresh. [pending] holds the PKCE
/// verifier across the same-tab redirect (sessionStorage on web).
class TokenStore {
  TokenStore(this._tokens, {KvStore? pending, this.persistAccess = true}) : _pending = pending ?? _tokens;

  final KvStore _tokens;
  final KvStore _pending;
  final bool persistAccess;
  TokenSet? _mem;

  static const _kTokens = 'loongs_admin.tokens';
  static const _kPending = 'loongs_admin.pending_login';

  Future<TokenSet?> read() async {
    if (_mem != null) return _mem;
    try {
      final raw = await _tokens.read(_kTokens);
      if (raw == null) return null;
      final t = TokenSet.decode(raw);
      return (t.accessToken.isEmpty && t.refreshToken == null) ? null : t;
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> write(TokenSet t) async {
    if (persistAccess) {
      await _tokens.write(_kTokens, t.encode());
      return;
    }
    _mem = t;
    final rt = t.refreshToken;
    if (rt == null) {
      await _tokens.delete(_kTokens);
    } else {
      // refresh token only; expiresAt = epoch → the next API call refreshes first
      await _tokens.write(_kTokens, jsonEncode({'r': rt}));
    }
  }

  Future<void> clear() async {
    _mem = null;
    await _tokens.delete(_kTokens);
  }

  /// {verifier, state, redirect_uri} for the web redirect round-trip.
  Future<void> savePending(Map<String, String> p) => _pending.write(_kPending, jsonEncode(p));

  Future<Map<String, String>?> takePending() async {
    final raw = await _pending.read(_kPending);
    await _pending.delete(_kPending);
    if (raw == null) return null;
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }
}
