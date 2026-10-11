import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

/// Secure storage (tokens in P1; here only the optional base URL override).
final secureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);

/// Current backend base URL (defaults to --dart-define API_BASE_URL).
class BaseUrlNotifier extends Notifier<String> {
  @override
  String build() => effectiveApiBaseUrl(pageHost: kIsWeb ? Uri.base.host : null);

  void set(String value) => state = value;
}

final baseUrlProvider =
    NotifierProvider<BaseUrlNotifier, String>(BaseUrlNotifier.new);

/// Shared dio instance; rebuilt when the base URL changes.
final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      responseType: ResponseType.json,
      // Keep non-2xx bodies (e.g. 503 degraded health) instead of throwing.
      validateStatus: (s) => s != null && s < 600,
    ),
  );
});
