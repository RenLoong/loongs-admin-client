import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth/auth_controller.dart';
import 'settings.dart';
import '../core/i18n.dart';

/// Server envelope `{code, message, data}` with code != 0.
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.data});

  final int code;
  final String message;
  final int? status;
  final Object? data;

  /// 422 validation details: field → messages.
  Map<String, List<String>> get errors {
    final d = data;
    if (d is Map && d['errors'] is Map) {
      return (d['errors'] as Map).map(
        (k, v) => MapEntry('$k', (v is List ? v : [v]).map((e) => '$e').toList()),
      );
    }
    return const {};
  }

  @override
  String toString() => message;
}

/// Page result `{list,total,page,page_size,...extra}`.
class PageResult {
  PageResult(this.raw);

  final Map<String, dynamic> raw;

  List<Map<String, dynamic>> get list =>
      ((raw['list'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  int get total => (raw['total'] as num?)?.toInt() ?? 0;
  int get page => (raw['page'] as num?)?.toInt() ?? 1;
  int get pageSize => (raw['page_size'] as num?)?.toInt() ?? 20;
}

/// Bearer + `Accept-Language` (the user's language, README §19) + refresh-once-on-401 (single-flight via AuthController.refreshAccess).
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._ref, this._dio);

  final Ref _ref;
  final Dio _dio;

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    options.headers['Accept-Language'] ??= _ref.read(languageProvider);
    final auth = _ref.read(authProvider.notifier);
    var tokens = _ref.read(authProvider).tokens;
    if (tokens != null && tokens.expiresSoon()) {
      await auth.refreshAccess();
      tokens = _ref.read(authProvider).tokens;
    }
    if (tokens != null) {
      options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) async {
    final o = response.requestOptions;
    if (response.statusCode == 401 && o.extra['retried'] != true) {
      final token = await _ref.read(authProvider.notifier).refreshAccess(sentToken: o.headers['Authorization'] as String?);
      if (token != null) {
        o.extra['retried'] = true;
        o.headers['Authorization'] = 'Bearer $token';
        try {
          return handler.resolve(await _dio.fetch<dynamic>(o));
        } on DioException catch (e) {
          return handler.reject(e);
        }
      }
    }
    handler.next(response);
  }
}

class Api {
  Api(this._dio);

  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(_dio.get<dynamic>(path, queryParameters: query));
  Future<dynamic> post(String path, [Object? body]) => _send(_dio.post<dynamic>(path, data: body));
  Future<dynamic> put(String path, [Object? body]) => _send(_dio.put<dynamic>(path, data: body));
  Future<dynamic> delete(String path) => _send(_dio.delete<dynamic>(path));

  /// Any method (used by the generic renderer's ActionRunner). [path] is relative to `/admin/api`
  /// or an absolute URL.
  Future<dynamic> send(String method, String path, {Map<String, dynamic>? query, Object? body}) =>
      _send(_dio.request<dynamic>(path, data: body, queryParameters: query, options: Options(method: method.toUpperCase())));

  Future<PageResult> page(String path, {Map<String, dynamic>? query}) async =>
      PageResult(((await get(path, query: query)) as Map).cast<String, dynamic>());

  /// Returns `data`; throws [ApiException] for code != 0 (message is user-facing Chinese text).
  static Future<dynamic> _send(Future<Response<dynamic>> f) async {
    final Response<dynamic> r;
    try {
      r = await f;
    } on DioException catch (e) {
      throw ApiException(-1, tr('网络错误：{msg}', {'msg': e.message ?? e.type.name}));
    }
    final b = r.data;
    if (b is Map && b.containsKey('code')) {
      final code = (b['code'] as num?)?.toInt() ?? -1;
      if (code == 0) return b['data'];
      throw ApiException(code, '${b['message'] ?? tr('请求失败')}', status: r.statusCode, data: b['data']);
    }
    throw ApiException(-1, 'HTTP ${r.statusCode}', status: r.statusCode);
  }
}

final apiDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: '${ref.watch(baseUrlProvider)}/admin/api',
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.json,
    validateStatus: (s) => s != null && s < 600,
  ));
  dio.interceptors.add(AuthInterceptor(ref, dio));
  return dio;
});

final apiProvider = Provider<Api>((ref) => Api(ref.watch(apiDioProvider)));
