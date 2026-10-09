/// Web build: no loopback listener (the web flow uses a same-tab redirect).
class LoopbackReceiver {
  LoopbackReceiver._();

  static Future<LoopbackReceiver> start() =>
      throw UnsupportedError('loopback redirect is desktop-only');

  String get redirectUri => throw UnsupportedError('desktop-only');

  Future<Map<String, String>> waitForCallback(Duration timeout) =>
      throw UnsupportedError('desktop-only');

  Future<void> close() async {}
}
