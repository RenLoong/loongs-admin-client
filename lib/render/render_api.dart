import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/api_client.dart';

/// Calls the APIs named in page descriptions (`/admin/api/...` paths) through the shared [Api]
/// (bearer token, refresh-on-401, `{code,message,data}` envelope).
class RenderApi {
  RenderApi(this.api, this.baseUrl);

  final Api api;
  final String baseUrl;

  static const _prefix = '/admin/api';

  /// `/admin/api/x` → `/x` (relative to the Api base `<host>/admin/api`); other absolute paths →
  /// `<host>/path`; full URLs unchanged.
  String resolve(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    if (path == _prefix) return '/';
    if (path.startsWith('$_prefix/')) return path.substring(_prefix.length);
    return '$baseUrl$path';
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => api.get(resolve(path), query: query);

  Future<PageResult> page(String path, {Map<String, dynamic>? query}) => api.page(resolve(path), query: query);

  Future<dynamic> send(String method, String path, {Object? body}) => api.send(method, resolve(path), body: body);
}

final renderApiProvider = Provider<RenderApi>((ref) => RenderApi(ref.watch(apiProvider), ref.watch(baseUrlProvider)));
