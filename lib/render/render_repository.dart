import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/auth/auth_controller.dart';
import '../core/settings.dart';
import 'page_desc.dart';
import '../core/i18n.dart';

/// Why a page description could not be shown.
enum RenderErrorKind { unauthorized, forbidden, notFound, upgrade, network, invalid }

class RenderError implements Exception {
  const RenderError(this.kind, this.message, {this.status, this.code});

  final RenderErrorKind kind;
  final String message;
  final int? status;
  final int? code;

  @override
  String toString() => message;
}

/// Page code + params (query of GET /admin/api/pages/{page}); value-equal for provider families.
@immutable
class PageRequest {
  PageRequest(this.page, [Map<String, dynamic> params = const {}])
      : params = {for (final k in (params.keys.toList()..sort())) if (params[k] != null && '${params[k]}' != '') k: '${params[k]}'};

  final String page;
  final Map<String, String> params;

  String get cacheKey => params.isEmpty ? page : '$page?${Uri(queryParameters: params).query}';

  @override
  bool operator ==(Object other) => other is PageRequest && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => cacheKey;
}

/// `X-Client-Env` for the PC client (informational; the server only trims by platform for pc).
String get clientEnv {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    _ => defaultTargetPlatform.name,
  };
}

/// GET /admin/api/pages/{page} with `X-Client-Platform: pc`, `X-Client-Env`, `X-Render-Schema` and
/// `If-None-Match` from the local cache (304 → cached description). The cache lives as long as the
/// signed-in user (provider is rebuilt on user change / logout); the server's ETag covers role,
/// permission, menu and schema changes, so every visit revalidates.
class RenderRepository {
  RenderRepository(this._dio, {this.language});

  final Dio _dio;

  /// Sent as `Accept-Language` (descriptions come back translated; null = interceptor default).
  final String? language;
  final Map<String, (String etag, PageDesc desc)> _cache = {};

  /// Requests answered from the cache via 304 (for tests / diagnostics).
  int notModified = 0;

  (String, PageDesc)? cached(PageRequest r) => _cache[r.cacheKey];

  void clear() => _cache.clear();

  Future<PageDesc> fetch(PageRequest req) async {
    final hit = _cache[req.cacheKey];
    final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(
        '/pages/${Uri.encodeComponent(req.page)}',
        queryParameters: req.params.isEmpty ? null : req.params,
        options: Options(headers: {
          'X-Client-Platform': 'pc',
          'X-Client-Env': clientEnv,
          'X-Render-Schema': '$kRenderSchema',
          'Accept-Language': ?language,
          'If-None-Match': ?hit?.$1,
        }),
      );
    } on DioException catch (e) {
      throw RenderError(RenderErrorKind.network, tr('网络错误：{msg}', {'msg': e.message ?? e.type.name}));
    }
    final status = res.statusCode ?? 0;
    if (status == 304 && hit != null) {
      notModified++;
      return hit.$2;
    }
    final b = res.data;
    final code = b is Map ? (b['code'] as num?)?.toInt() : null;
    final msg = b is Map ? '${b['message'] ?? ''}' : '';
    if (status == 200 && code == 0 && b is Map && b['data'] is Map) {
      final desc = PageDesc((b['data'] as Map).cast<String, dynamic>());
      if (desc.schema > kRenderSchema) {
        throw RenderError(RenderErrorKind.upgrade, tr('页面描述版本 {v} 高于客户端支持的 {max}，请升级客户端', {'v': desc.schema, 'max': kRenderSchema}), status: status);
      }
      final etag = res.headers.value('etag') ?? '"${desc.version}"';
      _cache[req.cacheKey] = (etag, desc);
      return desc;
    }
    _cache.remove(req.cacheKey);
    throw switch (status) {
      401 => RenderError(RenderErrorKind.unauthorized, msg.isEmpty ? tr('登录已失效，请重新登录') : msg, status: status, code: code),
      403 => RenderError(RenderErrorKind.forbidden, msg.isEmpty ? tr('无权限访问该页面') : msg, status: status, code: code),
      404 => RenderError(RenderErrorKind.notFound, msg.isEmpty ? tr('页面不存在') : msg, status: status, code: code),
      426 => RenderError(RenderErrorKind.upgrade, msg.isEmpty ? tr('客户端版本过旧，请升级后再试') : msg, status: status, code: code),
      _ => RenderError(RenderErrorKind.invalid, msg.isEmpty ? tr('页面加载失败（HTTP {status}）', {'status': status}) : msg, status: status, code: code),
    };
  }
}

/// One repository (and ETag cache) per signed-in user and language (descriptions are translated
/// server-side from Accept-Language; the server's ETag differs per locale as well).
final renderRepositoryProvider = Provider<RenderRepository>((ref) {
  ref.watch(authProvider.select((s) => s.profile?.id));
  return RenderRepository(ref.watch(apiDioProvider), language: ref.watch(languageProvider));
});

/// Description of one page; revalidated (If-None-Match) every time a page is opened.
final pageDescProvider = FutureProvider.autoDispose.family<PageDesc, PageRequest>(
  (ref, req) => ref.watch(renderRepositoryProvider).fetch(req),
);
