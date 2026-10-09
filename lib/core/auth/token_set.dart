import 'dart:convert';

class TokenSet {
  const TokenSet({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory TokenSet.fromTokenResponse(Map<String, dynamic> j, {DateTime? now}) {
    final at = j['access_token'];
    if (at is! String || at.isEmpty) {
      throw const FormatException('token response without access_token');
    }
    final expiresIn = (j['expires_in'] as num?)?.toInt() ?? 900;
    return TokenSet(
      accessToken: at,
      refreshToken: j['refresh_token'] as String?,
      expiresAt: (now ?? DateTime.now()).add(Duration(seconds: expiresIn)),
    );
  }

  factory TokenSet.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    // refresh-only records (session storage mode) have no 'a' / 'e': expired → refresh first
    return TokenSet(
      accessToken: (j['a'] as String?) ?? '',
      refreshToken: j['r'] as String?,
      expiresAt: DateTime.fromMillisecondsSinceEpoch((j['e'] as int?) ?? 0),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  /// True when the access token expires within [skew] (refresh proactively).
  bool expiresSoon({Duration skew = const Duration(seconds: 30), DateTime? now}) =>
      (now ?? DateTime.now()).add(skew).isAfter(expiresAt);

  String encode() => jsonEncode({
        'a': accessToken,
        'r': refreshToken,
        'e': expiresAt.millisecondsSinceEpoch,
      });
}
