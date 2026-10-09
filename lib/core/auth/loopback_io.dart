import 'dart:async';
import 'dart:io';
import '../../core/i18n.dart';

/// RFC 8252 §7.3 loopback redirect for desktop: listen on `127.0.0.1:<random>/callback`,
/// the system browser is redirected here with ?code&state (or ?error).
class LoopbackReceiver {
  LoopbackReceiver._(this._server, this.redirectUri);

  final HttpServer _server;

  /// Captured at bind time — [HttpServer.port] throws after [close].
  final String redirectUri;

  static Future<LoopbackReceiver> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LoopbackReceiver._(
      server,
      'http://127.0.0.1:${server.port}/callback',
    );
  }

  Future<Map<String, String>> waitForCallback(Duration timeout) async {
    try {
      await for (final req in _server.timeout(timeout)) {
        if (req.uri.path != '/callback') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          continue;
        }
        final q = req.uri.queryParameters;
        final ok = q.containsKey('code');
        req.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..headers.set('Cache-Control', 'no-store')
          ..write('<!doctype html><meta charset="utf-8"><title>LOONGS</title>'
              '<body style="font-family:sans-serif;text-align:center;padding-top:80px">'
              '<h2>${ok ? tr('登录完成') : tr('登录未完成')}</h2><p>${tr('可以关闭此页面并返回 LOONGS 平台管理。')}</p></body>');
        await req.response.close();
        return q;
      }
      throw TimeoutException('login callback not received');
    } finally {
      await close();
    }
  }

  Future<void> close() => _server.close(force: true);
}