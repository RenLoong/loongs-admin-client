import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

class HealthResult {
  HealthResult({
    required this.httpStatus,
    required this.elapsedMs,
    required this.body,
  });

  final int httpStatus;
  final int elapsedMs;
  final Map<String, dynamic> body;

  Map<String, dynamic> get data =>
      (body['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get status => data['status']?.toString() ?? 'unknown';
  bool get ok => body['code'] == 0 && status == 'ok';
  Map<String, dynamic> get checks =>
      (data['checks'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class HealthRepository {
  HealthRepository(this._dio);

  final Dio _dio;

  Future<HealthResult> fetch() async {
    final sw = Stopwatch()..start();
    final res = await _dio.get<Map<String, dynamic>>('/health');
    sw.stop();
    return HealthResult(
      httpStatus: res.statusCode ?? 0,
      elapsedMs: sw.elapsedMilliseconds,
      body: res.data ?? const {},
    );
  }
}

final healthRepositoryProvider =
    Provider<HealthRepository>((ref) => HealthRepository(ref.watch(dioProvider)));

/// Health check; `ref.invalidate(healthProvider)` re-runs it.
final healthProvider = FutureProvider.autoDispose<HealthResult>(
  (ref) => ref.watch(healthRepositoryProvider).fetch(),
);
