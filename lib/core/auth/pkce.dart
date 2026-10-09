import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// URL-safe random string without padding (RFC 7636 unreserved charset).
String randomUrlSafe([int bytes = 32]) {
  final r = Random.secure();
  final b = List<int>.generate(bytes, (_) => r.nextInt(256));
  return base64UrlEncode(b).replaceAll('=', '');
}

/// PKCE pair (S256 only; `plain` is rejected by the server).
class Pkce {
  Pkce._(this.verifier, this.challenge);

  factory Pkce.generate() {
    final verifier = randomUrlSafe(48); // 64 chars
    return Pkce._(verifier, challengeOf(verifier));
  }

  static String challengeOf(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  final String verifier;
  final String challenge;
}
