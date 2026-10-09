import 'package:dio/dio.dart';

import '../config.dart';
import 'pkce.dart';
import 'token_set.dart';

class OAuthError implements Exception {
  OAuthError(this.error, [this.description]);

  final String error;
  final String? description;

  /// invalid_grant etc. mean the refresh token is dead (rotated, reused, revoked, expired).
  bool get isFatal => error != 'network_error';

  @override
  String toString() => description == null ? error : '$error: $description';
}

/// Talks to loongs/oauth endpoints (authorization_code + PKCE S256, refresh rotation, revoke).
class OAuthClient {
  OAuthClient(String baseUrl, {Dio? dio})
      : _base = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (s) => s != null && s < 600,
            ));

  final String _base;
  final Dio _dio;

  Uri authorizeUrl({
    required String redirectUri,
    required Pkce pkce,
    required String state,
    String? uiLocales,
    String? uiTheme,
  }) =>
      Uri.parse('$_base/oauth/authorize').replace(queryParameters: {
        'response_type': 'code',
        'client_id': kOAuthClientId,
        'redirect_uri': redirectUri,
        'scope': kOAuthScope,
        'state': state,
        'code_challenge': pkce.challenge,
        'code_challenge_method': 'S256',
        // login page language / theme (OIDC ui_locales; ui_theme is a loongs extension)
        'ui_locales': ?uiLocales,
        'ui_theme': ?uiTheme,
      });

  Future<TokenSet> exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) =>
      _token({
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': redirectUri,
        'client_id': kOAuthClientId,
      });

  Future<TokenSet> refresh(String refreshToken) => _token({
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': kOAuthClientId,
      });

  /// RFC 7009; revoking the refresh token revokes its whole family server-side.
  Future<void> revoke(String token, {String hint = 'refresh_token'}) async {
    await _dio.post<dynamic>(
      '$_base/oauth/revoke',
      data: {'token': token, 'token_type_hint': hint, 'client_id': kOAuthClientId},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
  }

  Future<TokenSet> _token(Map<String, String> form) async {
    final Response<dynamic> r;
    try {
      r = await _dio.post<dynamic>(
        '$_base/oauth/token',
        data: form,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } on DioException catch (e) {
      throw OAuthError('network_error', e.message);
    }
    final body = r.data;
    if (r.statusCode == 200 && body is Map<String, dynamic>) {
      return TokenSet.fromTokenResponse(body);
    }
    if (body is Map) {
      throw OAuthError('${body['error'] ?? 'server_error'}', body['error_description'] as String?);
    }
    throw OAuthError('server_error', 'HTTP ${r.statusCode}');
  }
}
