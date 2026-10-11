/// Runtime API base URL from `domain.js` (`window.__LOONGS_API_BASE_URL__`) on web.
library;

export 'api_base_stub.dart' if (dart.library.js_interop) 'api_base_web.dart';
